PRAGMA foreign_keys = ON;
PRAGMA encoding = 'UTF-8';
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;

-- =====================================================
-- 1. Таблица пользователей
-- =====================================================
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    full_name TEXT NOT NULL,
    phone TEXT UNIQUE,
    email TEXT UNIQUE,
    role TEXT CHECK(role IN ('CLIENT', 'EMPLOYEE', 'ADMIN')) DEFAULT 'EMPLOYEE',
    password_hash TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    is_active INTEGER DEFAULT 1
);

-- =====================================================
-- 2. Таблица ячеек хранения
-- =====================================================
CREATE TABLE IF NOT EXISTS storage_cells (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    cell_number TEXT NOT NULL UNIQUE,
    zone TEXT,
    is_occupied INTEGER DEFAULT 0,
    is_blocked INTEGER DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- 3. Таблица заказов
-- =====================================================
CREATE TABLE IF NOT EXISTS orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    order_number TEXT NOT NULL UNIQUE,
    client_id INTEGER,
    employee_id INTEGER,
    storage_cell_id INTEGER,
    status TEXT CHECK(status IN ('RECEIVED', 'STORED', 'READY', 'ISSUED', 'RETURNED', 'LOST')) DEFAULT 'RECEIVED',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    received_at DATETIME,
    issued_at DATETIME,
    expiry_date DATE,
    barcode TEXT,
    track_number TEXT,
    notes TEXT,
    total_amount DECIMAL(10,2) DEFAULT 0,
    FOREIGN KEY (client_id) REFERENCES users(id),
    FOREIGN KEY (employee_id) REFERENCES users(id),
    FOREIGN KEY (storage_cell_id) REFERENCES storage_cells(id)
);

-- =====================================================
-- 4. Таблица товаров
-- =====================================================
CREATE TABLE IF NOT EXISTS products (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    article TEXT UNIQUE NOT NULL,
    barcode TEXT UNIQUE,
    price DECIMAL(10,2) NOT NULL,
    category TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- =====================================================
-- 5. Таблица позиций заказа
-- =====================================================
CREATE TABLE IF NOT EXISTS order_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id INTEGER,
    product_id INTEGER,
    quantity INTEGER NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
    FOREIGN KEY (product_id) REFERENCES products(id)
);

-- =====================================================
-- 6. Таблица чеков
-- =====================================================
CREATE TABLE IF NOT EXISTS receipts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id INTEGER UNIQUE,
    receipt_number TEXT UNIQUE NOT NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    printed INTEGER DEFAULT 0,
    FOREIGN KEY (order_id) REFERENCES orders(id)
);

-- =====================================================
-- 7. Таблица возвратов
-- =====================================================
CREATE TABLE IF NOT EXISTS returns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    order_id INTEGER,
    return_number TEXT UNIQUE NOT NULL,
    reason TEXT NOT NULL,
    refund_amount DECIMAL(10,2) NOT NULL,
    return_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    processed_by INTEGER,
    FOREIGN KEY (order_id) REFERENCES orders(id),
    FOREIGN KEY (processed_by) REFERENCES users(id)
);

-- =====================================================
-- 8. Индексы
-- =====================================================
CREATE INDEX IF NOT EXISTS idx_orders_number ON orders(order_number);
CREATE INDEX IF NOT EXISTS idx_orders_track ON orders(track_number);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_client ON orders(client_id);
CREATE INDEX IF NOT EXISTS idx_products_article ON products(article);
CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode);
CREATE INDEX IF NOT EXISTS idx_users_phone ON users(phone);

-- =====================================================
-- 9. Начальные данные
-- =====================================================
INSERT OR IGNORE INTO storage_cells (cell_number, zone) VALUES
    ('A-01-01', 'A'), ('A-01-02', 'A'), ('A-01-03', 'A'),
    ('B-01-01', 'B'), ('B-01-02', 'B'), ('B-01-03', 'B');

INSERT OR IGNORE INTO users (full_name, phone, email, role, password_hash) VALUES
    ('Платонов Олег Владимирович', '+74951234567', 'platonov@pvz.ru', 'ADMIN',
     '8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918');