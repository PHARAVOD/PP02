import os
import sys
import django
import pandas as pd
import logging
from datetime import datetime, timedelta
from pathlib import Path

# Настройка Django окружения
sys.path.append(str(Path(__file__).resolve().parent.parent))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'pvz_project.settings')
django.setup()

from django.contrib.auth import get_user_model
from django.utils import timezone
from pvz_app.models import Order, Product, OrderItem, StorageCell, Log

User = get_user_model()

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('import_orders.log', encoding='utf-8'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


class OrderImporter:
    """
    Класс для импорта заказов из Excel-файлов
    """

    def __init__(self, file_path):
        self.file_path = file_path
        self.success_count = 0
        self.error_count = 0
        self.errors = []

    def validate_file(self):
        """Проверка существования и формата файла"""
        if not os.path.exists(self.file_path):
            raise FileNotFoundError(f"Файл {self.file_path} не найден")

        if not self.file_path.endswith(('.xlsx', '.xls')):
            raise ValueError("Файл должен быть в формате Excel (.xlsx или .xls)")

        return True

    def read_excel(self):
        """Чтение Excel-файла"""
        try:
            df = pd.read_excel(self.file_path)
            logger.info(f"Загружено {len(df)} строк из файла {self.file_path}")
            return df
        except Exception as e:
            logger.error(f"Ошибка чтения файла: {e}")
            raise

    def process_client(self, row):
        """Создание или получение клиента"""
        phone = str(row.get('phone', '')).strip()
        full_name = row.get('full_name', '').strip()
        email = row.get('email', '').strip()

        if not phone:
            phone = f"+7{datetime.now().strftime('%y%m%d%H%M%S')}"

        client, created = User.objects.get_or_create(
            phone=phone,
            defaults={
                'full_name': full_name or 'Клиент',
                'email': email or None,
                'role': 'CLIENT',
                'password_hash': 'no_password'
            }
        )

        if created:
            logger.info(f"Создан новый клиент: {client.full_name}, тел: {client.phone}")

        return client

    def process_order(self, row, client):
        """Создание заказа"""
        order_number = str(row.get('order_number', '')).strip()

        if not order_number:
            raise ValueError("Отсутствует номер заказа")

        # Проверка дубликата
        if Order.objects.filter(order_number=order_number).exists():
            logger.warning(f"Заказ {order_number} уже существует, пропуск")
            return None

        # Срок хранения (по умолчанию 7 дней)
        expiry_days = int(row.get('expiry_days', 7))
        expiry_date = timezone.now().date() + timedelta(days=expiry_days)

        # Создание заказа
        order = Order.objects.create(
            order_number=order_number,
            client=client,
            status='RECEIVED',
            received_at=timezone.now(),
            expiry_date=expiry_date,
            track_number=str(row.get('track_number', '')).strip() or None,
            notes=str(row.get('notes', '')).strip() or None,
            total_amount=float(row.get('total_amount', 0))
        )

        logger.info(f"Создан заказ {order.order_number}")
        return order

    def process_products(self, order, row):
        """Обработка товаров в заказе"""
        products_str = str(row.get('products', '')).strip()
        quantities_str = str(row.get('quantities', '1')).strip()
        prices_str = str(row.get('prices', '0')).strip()

        if not products_str:
            logger.warning(f"Заказ {order.order_number} не содержит товаров")
            return

        products_list = [p.strip() for p in products_str.split(',')]
        quantities_list = [int(q.strip()) for q in quantities_str.split(',')]
        prices_list = [float(p.strip()) for p in prices_str.split(',')]

        # Выравнивание длин списков
        while len(quantities_list) < len(products_list):
            quantities_list.append(1)
        while len(prices_list) < len(products_list):
            prices_list.append(0)

        for i, article in enumerate(products_list):
            try:
                product = Product.objects.get(article=article)
                quantity = quantities_list[i] if i < len(quantities_list) else 1
                price = prices_list[i] if i < len(prices_list) else product.price

                OrderItem.objects.create(
                    order=order,
                    product=product,
                    quantity=quantity,
                    price=price
                )

                logger.debug(f"Товар {product.name} x{quantity} добавлен в заказ")

            except Product.DoesNotExist:
                error_msg = f"Товар с артикулом {article} не найден"
                logger.error(error_msg)
                self.errors.append(error_msg)

    def assign_cell(self, order):
        """Автоматическое назначение ячейки"""
        free_cell = StorageCell.objects.filter(is_occupied=False).first()

        if free_cell:
            order.storage_cell = free_cell
            order.status = 'STORED'
            order.save()
            free_cell.is_occupied = True
            free_cell.save()
            logger.info(f"Заказу {order.order_number} назначена ячейка {free_cell.cell_number}")
            return True
        else:
            logger.warning(f"Нет свободных ячеек для заказа {order.order_number}")
            return False

    def log_import(self, user=None):
        """Логирование импорта"""
        Log.objects.create(
            user=user,
            action='IMPORT_ORDERS',
            entity_type='Order',
            details={
                'file': self.file_path,
                'success': self.success_count,
                'errors': self.error_count,
                'error_list': self.errors[:10]
            }
        )

    def run(self, auto_assign_cell=True, user=None):
        """Запуск импорта"""
        logger.info("=" * 60)
        logger.info(f"Начало импорта из файла: {self.file_path}")
        logger.info("=" * 60)

        try:
            self.validate_file()
            df = self.read_excel()

            for index, row in df.iterrows():
                try:
                    # Обработка клиента
                    client = self.process_client(row)

                    # Обработка заказа
                    order = self.process_order(row, client)
                    if not order:
                        self.error_count += 1
                        continue

                    # Обработка товаров
                    self.process_products(order, row)

                    # Назначение ячейки
                    if auto_assign_cell:
                        self.assign_cell(order)

                    self.success_count += 1
                    logger.info(f"Строка {index + 2}: УСПЕХ - заказ {order.order_number}")

                except Exception as e:
                    self.error_count += 1
                    error_msg = f"Строка {index + 2}: ОШИБКА - {str(e)}"
                    logger.error(error_msg)
                    self.errors.append(error_msg)

            # Логирование
            self.log_import(user)

            # Итоги
            logger.info("=" * 60)
            logger.info(f"ИМПОРТ ЗАВЕРШЕН")
            logger.info(f"Успешно: {self.success_count}")
            logger.info(f"Ошибок: {self.error_count}")
            logger.info("=" * 60)

            return self.success_count, self.error_count, self.errors

        except Exception as e:
            logger.critical(f"Критическая ошибка: {e}")
            raise


def main():
    """Точка входа"""
    import argparse

    parser = argparse.ArgumentParser(description='Импорт заказов из Excel')
    parser.add_argument('file', help='Путь к Excel-файлу')
    parser.add_argument('--no-cell', action='store_true', help='Не назначать ячейки автоматически')
    parser.add_argument('--user-id', type=int, help='ID пользователя для логирования')

    args = parser.parse_args()

    # Получение пользователя
    user = None
    if args.user_id:
        try:
            user = User.objects.get(id=args.user_id)
        except User.DoesNotExist:
            logger.warning(f"Пользователь с ID {args.user_id} не найден")

    # Запуск импорта
    importer = OrderImporter(args.file)
    success, errors, error_list = importer.run(
        auto_assign_cell=not args.no_cell,
        user=user
    )

    # Код возврата
    sys.exit(0 if errors == 0 else 1)


if __name__ == '__main__':
    main()