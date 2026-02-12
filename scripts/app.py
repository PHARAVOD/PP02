from flask import Flask, request, jsonify, session
from flask_cors import CORS
import psycopg2
import hashlib
from datetime import datetime
import os

app = Flask(__name__)
app.secret_key = 'pvz-secret-key-2026'
CORS(app)


# Подключение к БД
def get_db():
    return psycopg2.connect(
        host='localhost',
        database='pvz_db',
        user='postgres',
        password='postgres'
    )


# ========== АВТОРИЗАЦИЯ ==========
@app.route('/api/login', methods=['POST'])
def login():
    data = request.json
    phone = data.get('phone')
    password = data.get('password')

    # Хеширование пароля
    password_hash = hashlib.sha256(password.encode()).hexdigest()

    conn = get_db()
    cur = conn.cursor()
    cur.execute(
        'SELECT id, full_name, role FROM users WHERE phone = %s AND password_hash = %s',
        (phone, password_hash)
    )
    user = cur.fetchone()
    cur.close()
    conn.close()

    if user:
        session['user_id'] = user[0]
        return jsonify({
            'success': True,
            'user': {
                'id': user[0],
                'name': user[1],
                'role': user[2]
            }
        })
    else:
        return jsonify({'success': False, 'error': 'Неверный телефон или пароль'}), 401


@app.route('/api/logout', methods=['POST'])
def logout():
    session.clear()
    return jsonify({'success': True})


# ========== ПОИСК ЗАКАЗОВ ==========
@app.route('/api/orders/search', methods=['GET'])
def search_orders():
    query = request.args.get('q', '')
    type = request.args.get('type', 'number')

    conn = get_db()
    cur = conn.cursor()

    if type == 'number':
        cur.execute('''
            SELECT o.*, c.cell_number, u.full_name as client_name 
            FROM orders o
            LEFT JOIN cells c ON o.cell_id = c.id
            LEFT JOIN users u ON o.client_id = u.id
            WHERE o.order_number ILIKE %s
        ''', (f'%{query}%',))
    elif type == 'phone':
        cur.execute('''
            SELECT o.*, c.cell_number, u.full_name as client_name 
            FROM orders o
            LEFT JOIN cells c ON o.cell_id = c.id
            LEFT JOIN users u ON o.client_id = u.id
            WHERE u.phone ILIKE %s
        ''', (f'%{query}%',))

    orders = cur.fetchall()
    cur.close()
    conn.close()

    result = []
    for o in orders:
        result.append({
            'id': o[0],
            'order_number': o[1],
            'client_name': o[12] if len(o) > 12 else '',
            'cell': o[10] if len(o) > 10 else '',
            'status': o[5],
            'created_at': str(o[6])
        })

    return jsonify(result)


# ========== ВЫДАЧА ЗАКАЗА ==========
@app.route('/api/orders/<int:order_id>/issue', methods=['POST'])
def issue_order(order_id):
    if 'user_id' not in session:
        return jsonify({'error': 'Не авторизован'}), 401

    conn = get_db()
    cur = conn.cursor()

    # Обновляем статус заказа
    cur.execute('''
        UPDATE orders 
        SET status = 'issued', 
            issued_at = NOW(), 
            employee_id = %s 
        WHERE id = %s
        RETURNING order_number
    ''', (session['user_id'], order_id))

    order = cur.fetchone()

    # Освобождаем ячейку
    cur.execute('''
        UPDATE cells SET is_occupied = FALSE 
        WHERE id = (SELECT cell_id FROM orders WHERE id = %s)
    ''', (order_id,))

    # Создаем чек
    cur.execute('''
        INSERT INTO receipts (order_id, receipt_number, total_amount, created_at)
        SELECT %s, CONCAT('RCP-', %s, '-', TO_CHAR(NOW(), 'YYYYMMDDHH24MISS')), 
               total_amount, NOW()
        FROM orders WHERE id = %s
        RETURNING receipt_number
    ''', (order_id, order_id, order_id))

    receipt = cur.fetchone()
    conn.commit()
    cur.close()
    conn.close()

    return jsonify({
        'success': True,
        'receipt_number': receipt[0],
        'message': f'Заказ {order[0]} выдан'
    })


# ========== ВОЗВРАТ ==========
@app.route('/api/orders/<int:order_id>/return', methods=['POST'])
def return_order(order_id):
    data = request.json
    reason = data.get('reason', '')

    conn = get_db()
    cur = conn.cursor()

    cur.execute('''
        INSERT INTO returns (order_id, reason, amount, created_at)
        SELECT %s, %s, total_amount, NOW()
        FROM orders WHERE id = %s
        RETURNING id
    ''', (order_id, reason, order_id))

    return_id = cur.fetchone()[0]

    cur.execute('UPDATE orders SET status = %s WHERE id = %s', ('returned', order_id))
    conn.commit()
    cur.close()
    conn.close()

    return jsonify({'success': True, 'return_id': return_id})


# ========== ЯЧЕЙКИ ==========
@app.route('/api/cells/free', methods=['GET'])
def get_free_cells():
    conn = get_db()
    cur = conn.cursor()
    cur.execute('SELECT id, cell_number FROM cells WHERE is_occupied = FALSE ORDER BY cell_number')
    cells = cur.fetchall()
    cur.close()
    conn.close()

    return jsonify([{'id': c[0], 'number': c[1]} for c in cells])


@app.route('/api/orders/<int:order_id>/assign_cell', methods=['POST'])
def assign_cell(order_id):
    data = request.json
    cell_id = data.get('cell_id')

    conn = get_db()
    cur = conn.cursor()

    # Проверяем свободна ли ячейка
    cur.execute('SELECT is_occupied FROM cells WHERE id = %s', (cell_id,))
    is_occupied = cur.fetchone()[0]

    if is_occupied:
        return jsonify({'error': 'Ячейка занята'}), 400

    # Назначаем ячейку
    cur.execute('UPDATE cells SET is_occupied = TRUE WHERE id = %s', (cell_id,))
    cur.execute('UPDATE orders SET cell_id = %s, status = %s WHERE id = %s',
                (cell_id, 'stored', order_id))

    conn.commit()
    cur.close()
    conn.close()

    return jsonify({'success': True})


# ========== СТАТИСТИКА ==========
@app.route('/api/stats', methods=['GET'])
def get_stats():
    conn = get_db()
    cur = conn.cursor()

    # Заказов сегодня
    cur.execute("SELECT COUNT(*) FROM orders WHERE DATE(created_at) = CURRENT_DATE")
    today_orders = cur.fetchone()[0]

    # Выдано сегодня
    cur.execute("SELECT COUNT(*) FROM orders WHERE DATE(issued_at) = CURRENT_DATE")
    today_issued = cur.fetchone()[0]

    # В работе
    cur.execute("SELECT COUNT(*) FROM orders WHERE status IN ('received', 'stored')")
    active_orders = cur.fetchone()[0]

    # Свободные ячейки
    cur.execute("SELECT COUNT(*) FROM cells WHERE is_occupied = FALSE")
    free_cells = cur.fetchone()[0]

    cur.close()
    conn.close()

    return jsonify({
        'today_orders': today_orders,
        'today_issued': today_issued,
        'active_orders': active_orders,
        'free_cells': free_cells
    })


if __name__ == '__main__':
    app.run(debug=True, port=5000)