-- Создание базы данных
CREATE DATABASE pvz_management
    WITH ENCODING = 'UTF8'
    OWNER = postgres;

-- Подключение к БД
\c pvz_management;

-- =====================================================
-- 1. Создание перечислимых типов
-- =====================================================
CREATE TYPE user_role AS ENUM ('CLIENT', 'EMPLOYEE', 'ADMIN');
CREATE TYPE order_status AS ENUM ('RECEIVED', 'STORED', 'READY', 'ISSUED', 'RETURNED', 'LOST', 'EXPIRED');

-- =====================================================
-- 2. Таблица пользователей
-- =====================================================
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    phone VARCHAR(20) UNIQUE,
    email VARCHAR(100) UNIQUE,
    role user_role NOT NULL DEFAULT 'EMPLOYEE',
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    last_login TIMESTAMP,
    avatar_url TEXT
);

-- =====================================================
-- 3. Таблица ячеек хранения
-- =====================================================
CREATE TABLE storage_cells (
    id BIGSERIAL PRIMARY KEY,
    cell_number VARCHAR(20) NOT NULL UNIQUE,
    zone VARCHAR(50),
    shelf VARCHAR(20),
    row_num INTEGER,
    level INTEGER,
    is_occupied BOOLEAN DEFAULT FALSE,
    is_blocked BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- 4. Таблица заказов
-- =====================================================
CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    order_number VARCHAR(50) NOT NULL UNIQUE,
    client_id BIGINT REFERENCES users(id),
    employee_id BIGINT REFERENCES users(id),
    storage_cell_id BIGINT REFERENCES storage_cells(id),
    status order_status NOT NULL DEFAULT 'RECEIVED',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    received_at TIMESTAMP,
    issued_at TIMESTAMP,
    expiry_date DATE NOT NULL,
    barcode VARCHAR(100),
    track_number VARCHAR(100),
    notes TEXT,
    is_paid BOOLEAN DEFAULT FALSE,
    total_amount DECIMAL(10,2) DEFAULT 0
);

-- =====================================================
-- 5. Таблица товаров
-- =====================================================
CREATE TABLE products (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    article VARCHAR(100) UNIQUE NOT NULL,
    barcode VARCHAR(100) UNIQUE,
    price DECIMAL(10,2) NOT NULL,
    old_price DECIMAL(10,2),
    weight DECIMAL(10,3),
    category VARCHAR(100),
    brand VARCHAR(100),
    description TEXT,
    image_url TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- 6. Таблица позиций заказа
-- =====================================================
CREATE TABLE order_items (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT REFERENCES orders(id) ON DELETE CASCADE,
    product_id BIGINT REFERENCES products(id),
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    price DECIMAL(10,2) NOT NULL,
    discount DECIMAL(10,2) DEFAULT 0,
    total DECIMAL(10,2) GENERATED ALWAYS AS (price * quantity - discount) STORED
);

-- =====================================================
-- 7. Таблица чеков
-- =====================================================
CREATE TABLE receipts (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT REFERENCES orders(id) UNIQUE,
    receipt_number VARCHAR(50) UNIQUE NOT NULL,
    fiscal_drive_number VARCHAR(50),
    fiscal_document_number VARCHAR(50),
    fiscal_sign VARCHAR(100),
    total_amount DECIMAL(10,2) NOT NULL,
    tax_amount DECIMAL(10,2) DEFAULT 0,
    payment_type VARCHAR(50) DEFAULT 'cash',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    printed BOOLEAN DEFAULT FALSE,
    sent_to_email BOOLEAN DEFAULT FALSE
);

-- =====================================================
-- 8. Таблица возвратов
-- =====================================================
CREATE TABLE returns (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT REFERENCES orders(id),
    return_number VARCHAR(50) UNIQUE NOT NULL,
    reason VARCHAR(255) NOT NULL,
    reason_details TEXT,
    refund_amount DECIMAL(10,2) NOT NULL,
    return_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processed_by BIGINT REFERENCES users(id),
    status VARCHAR(50) DEFAULT 'pending',
    items_returned JSONB
);

-- =====================================================
-- 9. Таблица логов
-- =====================================================
CREATE TABLE logs (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES users(id),
    action VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50),
    entity_id BIGINT,
    details JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- 10. Таблица настроек системы
-- =====================================================
CREATE TABLE settings (
    id BIGSERIAL PRIMARY KEY,
    key VARCHAR(100) UNIQUE NOT NULL,
    value TEXT,
    description TEXT,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_by BIGINT REFERENCES users(id)
);

-- =====================================================
-- 11. Индексы для ускорения поиска
-- =====================================================
CREATE INDEX idx_orders_order_number ON orders(order_number);
CREATE INDEX idx_orders_track_number ON orders(track_number);
CREATE INDEX idx_orders_barcode ON orders(barcode);
CREATE INDEX idx_orders_client_id ON orders(client_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_created_at ON orders(created_at);
CREATE INDEX idx_orders_expiry_date ON orders(expiry_date);
CREATE INDEX idx_storage_cells_cell_number ON storage_cells(cell_number);
CREATE INDEX idx_storage_cells_is_occupied ON storage_cells(is_occupied);
CREATE INDEX idx_products_article ON products(article);
CREATE INDEX idx_products_barcode ON products(barcode);
CREATE INDEX idx_products_name ON products(name);
CREATE INDEX idx_users_phone ON users(phone);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_returns_order_id ON returns(order_id);
CREATE INDEX idx_returns_return_date ON returns(return_date);
CREATE INDEX idx_logs_user_id ON logs(user_id);
CREATE INDEX idx_logs_created_at ON logs(created_at);
CREATE INDEX idx_logs_action ON logs(action);

-- =====================================================
-- 12. Триггеры
-- =====================================================
-- Триггер для автоматического обновления updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_orders_updated_at
    BEFORE UPDATE ON orders
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_storage_cells_updated_at
    BEFORE UPDATE ON storage_cells
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Триггер для автоматического обновления expiry_date
CREATE OR REPLACE FUNCTION set_default_expiry_date()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.expiry_date IS NULL THEN
        NEW.expiry_date = CURRENT_DATE + INTERVAL '7 days';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_orders_expiry_date
    BEFORE INSERT ON orders
    FOR EACH ROW
    EXECUTE FUNCTION set_default_expiry_date();

-- =====================================================
-- 13. Начальное заполнение справочников
-- =====================================================
-- Ячейки хранения
INSERT INTO storage_cells (cell_number, zone, shelf, row_num, level) VALUES
    ('A-01-01', 'A', '1', 1, 1), ('A-01-02', 'A', '1', 1, 2), ('A-01-03', 'A', '1', 1, 3),
    ('A-02-01', 'A', '2', 2, 1), ('A-02-02', 'A', '2', 2, 2), ('A-02-03', 'A', '2', 2, 3),
    ('B-01-01', 'B', '1', 1, 1), ('B-01-02', 'B', '1', 1, 2), ('B-01-03', 'B', '1', 1, 3),
    ('B-02-01', 'B', '2', 2, 1), ('B-02-02', 'B', '2', 2, 2), ('B-02-03', 'B', '2', 2, 3),
    ('C-01-01', 'C', '1', 1, 1), ('C-01-02', 'C', '1', 1, 2), ('C-01-03', 'C', '1', 1, 3),
    ('C-02-01', 'C', '2', 2, 1), ('C-02-02', 'C', '2', 2, 2), ('C-02-03', 'C', '2', 2, 3);

-- Настройки системы
INSERT INTO settings (key, value, description) VALUES
    ('company_name', 'ИП Платонов О.В.', 'Наименование организации'),
    ('inn', '772312345678', 'ИНН организации'),
    ('address', 'г. Москва, ул. Строителей, д. 5, пом. 1', 'Адрес ПВЗ'),
    ('storage_days', '7', 'Срок хранения заказа (дней)'),
    ('receipt_prefix', 'ПВЗ-', 'Префикс номера чека'),
    ('return_prefix', 'ВОЗ-', 'Префикс номера возврата'),
    ('backup_time', '23:00', 'Время автоматического резервного копирования'),
    ('backup_count', '5', 'Количество хранимых резервных копий');

-- Создание администратора (пароль: admin123, хеш SHA256)
INSERT INTO users (full_name, phone, email, role, password_hash) VALUES
    ('Платонов Олег Владимирович', '+74951234567', 'platonov@pvz.ru', 'ADMIN',
     '8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918');