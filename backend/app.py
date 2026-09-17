import os
import re
import time
import json
import datetime
import bcrypt
import pymysql
import requests
from flask import Flask, request, jsonify
from flask_cors import CORS
from dotenv import load_dotenv

load_dotenv()

app = Flask(__name__)
CORS(app, resources={r"/*": {"origins": "*"}})

# MySQL configuration
DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
DB_USER = os.getenv("DB_USER", "root")
DB_PASS = os.getenv("DB_PASS", "")
DB_NAME = os.getenv("DB_NAME", "medsafe_db")
DB_PORT = int(os.getenv("DB_PORT", 3306))
FLASK_PORT = int(os.getenv("FLASK_PORT", 5000))

def get_db_connection(max_retries=3, delay=1):
    """Establishes a MySQL connection with automatic retry logic for WAMP/MySQL restarts."""
    for attempt in range(1, max_retries + 1):
        try:
            conn = pymysql.connect(
                host=DB_HOST,
                user=DB_USER,
                password=DB_PASS,
                database=DB_NAME,
                port=DB_PORT,
                autocommit=True,
                connect_timeout=5,
                read_timeout=10,
                write_timeout=10,
                cursorclass=pymysql.cursors.DictCursor
            )
            # Verify connection health
            conn.ping(reconnect=True)
            return conn
        except pymysql.Error as err:
            print(f"[DB] Connection attempt {attempt}/{max_retries} failed: {err}")
            if attempt < max_retries:
                time.sleep(delay)
            else:
                raise err

def test_db_connection():
    """Returns True if MySQL is reachable and usable, False otherwise."""
    try:
        conn = get_db_connection(max_retries=1, delay=0)
        with conn.cursor() as cursor:
            cursor.execute("SELECT 1")
        conn.close()
        return True
    except Exception as e:
        print(f"[DB Check] Failed: {e}")
        return False

@app.before_request
def log_request_info():
    if request.path != '/api/health' and request.path != '/':
        print(f"[FLASK] {request.method} {request.path} from {request.remote_addr}")

# ───────────────────────────────────────────────────────────────────────────────
# HEALTH CHECK ENDPOINT
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/api/health', methods=['GET', 'OPTIONS'])
@app.route('/backend/health.php', methods=['GET', 'OPTIONS'])
def health_check():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    db_ok = test_db_connection()
    status_str = "ok" if db_ok else "degraded"
    http_code = 200 if db_ok else 503

    return jsonify({
        "status": status_str,
        "flask": "ok",
        "database": "ok" if db_ok else "error",
        "timestamp": datetime.datetime.now().isoformat(),
        "version": "1.0.0"
    }), http_code

def check_password(password_plain, stored_hash):
    if not password_plain or not stored_hash:
        return False
    if isinstance(stored_hash, str):
        if stored_hash.startswith('$2y$'):
            stored_hash = '$2b$' + stored_hash[4:]
        stored_hash_bytes = stored_hash.encode('utf-8')
    else:
        stored_hash_bytes = stored_hash
    try:
        return bcrypt.checkpw(password_plain.encode('utf-8'), stored_hash_bytes)
    except Exception as e:
        print(f"Bcrypt verification error: {e}")
        return False

def hash_password(password_plain):
    salt = bcrypt.gensalt()
    return bcrypt.hashpw(password_plain.encode('utf-8'), salt).decode('utf-8')

# ── Helper for Date/Time serialization ─────────────────────────────────────────
def format_datetime(dt):
    if isinstance(dt, (datetime.datetime, datetime.date)):
        return dt.isoformat()
    return str(dt) if dt else ""

# ───────────────────────────────────────────────────────────────────────────────
# 1. LOGIN
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/login.php', methods=['POST', 'OPTIONS'])
@app.route('/login', methods=['POST', 'OPTIONS'])
def login():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    data = request.get_json(silent=True) or {}
    email = data.get('email', '').strip().lower()
    password = data.get('password', '')
    role = data.get('role', 'sales_rep')

    if not email or not password:
        return jsonify({"success": False, "message": "Email and password are required."}), 200

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute(
                "SELECT id, name, email, phone, password_hash, role, created_at FROM users WHERE email = %s AND role = %s",
                (email, role)
            )
            user = cursor.fetchone()
        conn.close()

        if not user or not check_password(password, user['password_hash']):
            return jsonify({"success": False, "message": "Invalid credentials."}), 200

        role_label = "Administrator" if user['role'] == 'admin' else "Sales Representative"
        token = f"wamp_token_{user['id']}_{int(time.time())}"

        return jsonify({
            "success": True,
            "message": "Login successful!",
            "data": {
                "user": {
                    "id": int(user['id']),
                    "name": user['name'],
                    "email": user['email'],
                    "phone": user['phone'],
                    "role": user['role'],
                    "role_label": role_label,
                    "is_active": True,
                    "created_at": format_datetime(user['created_at'])
                },
                "access_token": token
            }
        }), 200
    except Exception as e:
        return jsonify({"success": False, "message": f"Connection error: {str(e)}"}), 200

# ───────────────────────────────────────────────────────────────────────────────
# 2. REGISTER
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/register.php', methods=['POST', 'OPTIONS'])
@app.route('/register', methods=['POST', 'OPTIONS'])
def register():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    data = request.get_json(silent=True) or {}
    name = data.get('name', '').strip()
    email = data.get('email', '').strip().lower()
    phone = data.get('phone', '').strip()
    password = data.get('password', '')
    role = data.get('role', 'sales_rep')
    if role not in ['sales_rep', 'admin']:
        role = 'sales_rep'

    if not name or not email or not phone or not password:
        return jsonify({"success": False, "message": "All fields are required."}), 200

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute("SELECT id FROM users WHERE email = %s", (email,))
            if cursor.fetchone():
                conn.close()
                return jsonify({"success": False, "message": "Email already registered. Please login."}), 200

            pwd_hash = hash_password(password)
            cursor.execute(
                "INSERT INTO users (name, email, phone, password_hash, role) VALUES (%s, %s, %s, %s, %s)",
                (name, email, phone, pwd_hash, role)
            )
            user_id = cursor.lastrowid
        conn.close()

        role_label = "Administrator" if role == 'admin' else "Sales Representative"
        token = f"wamp_token_{user_id}_{int(time.time())}"

        return jsonify({
            "success": True,
            "message": "Registration successful!",
            "data": {
                "user": {
                    "id": user_id,
                    "name": name,
                    "email": email,
                    "phone": phone,
                    "role": role,
                    "role_label": role_label,
                    "is_active": True,
                    "created_at": datetime.datetime.now().isoformat()
                },
                "access_token": token
            }
        }), 200
    except Exception as e:
        return jsonify({"success": False, "message": f"Registration failed: {str(e)}"}), 200

# ───────────────────────────────────────────────────────────────────────────────
# 3. GET DATA (Doctors & Clinics)
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/get_data.php', methods=['GET', 'POST', 'OPTIONS'])
@app.route('/get_data', methods=['GET', 'POST', 'OPTIONS'])
def get_data():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    user_id = request.args.get('user_id') or (request.get_json(silent=True) or {}).get('user_id')
    role = request.args.get('role') or (request.get_json(silent=True) or {}).get('role')

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            if role == 'sales_rep' and user_id:
                cursor.execute(
                    "SELECT id, name, speciality, phone, area, added_by FROM doctors WHERE (is_deleted = 0 OR is_deleted IS NULL) AND (added_by = 0 OR added_by IS NULL OR added_by = %s) ORDER BY name ASC",
                    (user_id,)
                )
                doctors = cursor.fetchall()

                cursor.execute(
                    "SELECT id, name, lat, lng, address, phone, map_url, area, added_by FROM clinics WHERE (is_deleted = 0 OR is_deleted IS NULL) AND (added_by = 0 OR added_by IS NULL OR added_by = %s) ORDER BY name ASC",
                    (user_id,)
                )
                raw_clinics = cursor.fetchall()
            else:
                cursor.execute("SELECT id, name, speciality, phone, area, added_by FROM doctors WHERE (is_deleted = 0 OR is_deleted IS NULL) ORDER BY name ASC")
                doctors = cursor.fetchall()

                cursor.execute("SELECT id, name, lat, lng, address, phone, map_url, area, added_by FROM clinics WHERE (is_deleted = 0 OR is_deleted IS NULL) ORDER BY name ASC")
                raw_clinics = cursor.fetchall()

            clinics = [
                {
                    "id": c.get("id", 0),
                    "name": c["name"],
                    "lat": float(c["lat"]),
                    "lng": float(c["lng"]),
                    "address": c.get("address", ""),
                    "phone": c.get("phone", ""),
                    "map_url": c.get("map_url", ""),
                    "area": c.get("area", ""),
                    "added_by": c.get("added_by", 0)
                }
                for c in raw_clinics
            ]

            cursor.execute("SELECT DISTINCT doctor_name, clinic_name, clinic_lat, clinic_lng, clinic_address, area FROM tasks WHERE doctor_name != '' AND clinic_name != '' ORDER BY id DESC")
            raw_combos = cursor.fetchall()
            combinations = [
                {
                    "doctor_name": cb["doctor_name"],
                    "clinic_name": cb["clinic_name"],
                    "clinic_lat": float(cb["clinic_lat"] or 0),
                    "clinic_lng": float(cb["clinic_lng"] or 0),
                    "clinic_address": cb.get("clinic_address", ""),
                    "area": cb.get("area", "")
                }
                for cb in raw_combos
            ]

            cursor.execute("CREATE TABLE IF NOT EXISTS areas (id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100) NOT NULL UNIQUE, added_by INT UNSIGNED NOT NULL DEFAULT 0, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP)")
            cursor.execute("CREATE TABLE IF NOT EXISTS deleted_areas (id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY, area VARCHAR(100) NOT NULL UNIQUE, deleted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP)")
            cursor.execute("SELECT area FROM deleted_areas")
            deleted_areas = [str(r["area"]).strip().lower() for r in cursor.fetchall() if r.get("area")]

            areas_set = ["All Areas"]
            default_areas = ["Chennai", "Villupuram", "Cuddalore", "Tindivanam"]
            for da in default_areas:
                if da not in areas_set and da.lower() not in deleted_areas:
                    areas_set.append(da)

            cursor.execute("SELECT name FROM areas")
            for r in cursor.fetchall():
                a = str(r.get("name") or "").strip()
                if a and a not in areas_set and a.lower() not in deleted_areas:
                    areas_set.append(a)

            for d in doctors:
                a = str(d.get("area") or "").strip()
                if a and a not in areas_set and a.lower() not in deleted_areas:
                    areas_set.append(a)
            for c in clinics:
                a = str(c.get("area") or "").strip()
                if a and a not in areas_set and a.lower() not in deleted_areas:
                    areas_set.append(a)
            for cb in combinations:
                a = str(cb.get("area") or "").strip()
                if a and a not in areas_set and a.lower() not in deleted_areas:
                    areas_set.append(a)

        conn.close()

        return jsonify({
            "areas": areas_set,
            "doctors": doctors,
            "clinics": clinics,
            "combinations": combinations
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ───────────────────────────────────────────────────────────────────────────────
# 4. GET USER TASKS
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/get_user_tasks.php', methods=['GET', 'OPTIONS'])
@app.route('/get_user_tasks', methods=['GET', 'OPTIONS'])
def get_user_tasks():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    user_id = request.args.get('user_id', 0, type=int)
    sales_rep_name = request.args.get('sales_rep_name', '').strip()
    fetch_all = request.args.get('all', '0') == '1'
    from_date = request.args.get('from_date', '').strip().replace('/', '-')
    to_date = request.args.get('to_date', '').strip().replace('/', '-')

    def normalize_date(d_str):
        if not d_str:
            return None
        for fmt in ('%Y-%m-%d', '%d-%m-%Y', '%m-%d-%Y'):
            try:
                return datetime.datetime.strptime(d_str, fmt).strftime('%Y-%m-%d')
            except ValueError:
                pass
        return None

    from_ymd = normalize_date(from_date)
    to_ymd = normalize_date(to_date)

    date_conditions = []
    date_params = []
    if from_ymd and to_ymd:
        date_conditions.append("DATE(COALESCE(checkout_date, created_at)) >= %s AND DATE(COALESCE(checkout_date, created_at)) <= %s")
        date_params.extend([from_ymd, to_ymd])
    elif from_ymd:
        date_conditions.append("DATE(COALESCE(checkout_date, created_at)) >= %s")
        date_params.append(from_ymd)
    elif to_ymd:
        date_conditions.append("DATE(COALESCE(checkout_date, created_at)) <= %s")
        date_params.append(to_ymd)

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            if fetch_all:
                if date_conditions:
                    where_clause = " AND ".join(date_conditions)
                    cursor.execute(f"SELECT * FROM tasks WHERE {where_clause} ORDER BY created_at DESC", tuple(date_params))
                else:
                    cursor.execute("SELECT * FROM tasks ORDER BY created_at DESC")
            elif user_id > 0 or sales_rep_name:
                conditions = []
                params = []
                if user_id > 0:
                    conditions.append("user_id = %s")
                    params.append(user_id)
                if sales_rep_name:
                    conditions.append("sales_rep_name LIKE %s")
                    params.append(f"%{sales_rep_name}%")
                where_clause = "(" + " OR ".join(conditions) + ")"
                if date_conditions:
                    where_clause += " AND " + " AND ".join(date_conditions)
                    params.extend(date_params)
                cursor.execute(f"SELECT * FROM tasks WHERE {where_clause} ORDER BY created_at DESC", tuple(params))
            else:
                cursor.execute("SELECT * FROM tasks WHERE 1=0")
            
            rows = cursor.fetchall()
        conn.close()

        is_admin_req = (fetch_all or role == 'admin' or request.args.get('is_admin') == '1')

        tasks = []
        for row in rows:
            t_item = {
                "id": int(row['id']),
                "task_id": int(row['id']),
                "user_id": int(row.get('user_id') or 0),
                "sales_rep_name": str(row.get('sales_rep_name') or ''),
                "task_basis": str(row.get('task_basis') or ''),
                "doctor_name": str(row.get('doctor_name') or ''),
                "clinic_name": str(row.get('clinic_name') or ''),
                "task_category": str(row.get('task_category') or ''),
                "area": str(row.get('area') or ''),
                "source_lat": float(row['source_lat']) if row.get('source_lat') is not None else None,
                "source_lng": float(row['source_lng']) if row.get('source_lng') is not None else None,
                "source_address": str(row.get('source_address') or ''),
                "clinic_lat": float(row.get('clinic_lat') or 0),
                "clinic_lng": float(row.get('clinic_lng') or 0),
                "clinic_address": str(row.get('clinic_address') or ''),
                "notes": str(row.get('notes') or ''),
                "status": str(row.get('status') or 'pending'),
                "checkout_type": str(row.get('checkout_type') or ''),
                "checkout_date": str(row.get('checkout_date') or ''),
                "checkout_time": str(row.get('checkout_time') or ''),
                "checked_out_at": format_datetime(row.get('checked_out_at')),
                "checkout_lat": float(row['checkout_lat']) if row.get('checkout_lat') is not None else None,
                "checkout_lng": float(row['checkout_lng']) if row.get('checkout_lng') is not None else None,
                "destination_distance_meters": float(row['destination_distance_meters']) if row.get('destination_distance_meters') is not None else None,
                "final_distance_meters": float(row['final_distance_meters']) if row.get('final_distance_meters') is not None else (float(row['destination_distance_meters']) if row.get('destination_distance_meters') is not None else None),
                "destination_reached_at": format_datetime(row.get('destination_reached_at')),
                "target_deadline_at": format_datetime(row.get('target_deadline_at')),
                "target_duration_seconds": int(row.get('target_duration_seconds') or 300),
                "is_inside_destination": bool(row.get('is_inside_destination')),
                "time_inside_destination_seconds": int(row.get('time_inside_destination_seconds') or 0),
                "last_destination_distance_meters": float(row['last_destination_distance_meters']) if row.get('last_destination_distance_meters') is not None else None,
                "completion_result": str(row.get('completion_result') or ''),
                "overtime_duration_seconds": int(row.get('overtime_duration_seconds') or 0),
                "created_at": format_datetime(row.get('created_at')),
                "updated_at": format_datetime(row.get('updated_at')),
            }
            if is_admin_req:
                t_item["overtime_reason"] = str(row.get('overtime_reason') or '')

            tasks.append(t_item)

        return jsonify({
            "success": True,
            "count": len(tasks),
            "user_id": user_id,
            "rep_name": sales_rep_name,
            "tasks": tasks
        }), 200
    except Exception as e:
        return jsonify({"success": False, "message": f"DB error: {str(e)}"}), 200

# ───────────────────────────────────────────────────────────────────────────────
# 5. GET PENDING TASKS
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/get_pending_tasks.php', methods=['GET', 'OPTIONS'])
@app.route('/get_pending_tasks', methods=['GET', 'OPTIONS'])
def get_pending_tasks():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    user_id = request.args.get('user_id', 0, type=int)
    if not user_id:
        return jsonify({"success": False, "message": "user_id is required."}), 200

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute(
                "SELECT id, sales_rep_name, task_basis, doctor_name, clinic_name, task_category, area, clinic_lat, clinic_lng, clinic_address, notes, status, created_at FROM tasks WHERE user_id = %s AND status = 'pending' ORDER BY created_at DESC",
                (user_id,)
            )
            rows = cursor.fetchall()
        conn.close()

        tasks = [
            {
                "id": int(row['id']),
                "user_id": int(row.get('user_id') or 0),
                "sales_rep_name": row.get('sales_rep_name') or '',
                "task_basis": row.get('task_basis') or '',
                "doctor_name": row.get('doctor_name') or '',
                "clinic_name": row.get('clinic_name') or '',
                "task_category": row.get('task_category') or '',
                "area": str(row.get('area') or ''),
                "source_lat": float(row['source_lat']) if row.get('source_lat') is not None else None,
                "source_lng": float(row['source_lng']) if row.get('source_lng') is not None else None,
                "source_address": row.get('source_address') or '',
                "clinic_lat": float(row['clinic_lat']) if row.get('clinic_lat') is not None else 0.0,
                "clinic_lng": float(row['clinic_lng']) if row.get('clinic_lng') is not None else 0.0,
                "clinic_address": row.get('clinic_address') or '',
                "notes": row.get('notes') or '',
                "status": row.get('status') or 'pending',
                "checkout_type": row.get('checkout_type') or '',
                "checkout_date": str(row.get('checkout_date') or ''),
                "checkout_time": str(row.get('checkout_time') or ''),
                "checked_out_at": format_datetime(row.get('checked_out_at')),
                "checkout_lat": float(row['checkout_lat']) if row.get('checkout_lat') is not None else None,
                "checkout_lng": float(row['checkout_lng']) if row.get('checkout_lng') is not None else None,
                "destination_distance_meters": float(row['destination_distance_meters']) if row.get('destination_distance_meters') is not None else None,
                "created_at": format_datetime(row.get('created_at')),
                "updated_at": format_datetime(row.get('updated_at')),
            }
            for row in rows
        ]

        return jsonify({"success": True, "tasks": tasks}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 200

# ───────────────────────────────────────────────────────────────────────────────
# 6. SAVE TASK
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/save_task.php', methods=['POST', 'OPTIONS'])
@app.route('/save_task', methods=['POST', 'OPTIONS'])
def save_task():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    data = request.get_json(silent=True) or {}
    task_id = int(data.get('task_id') or data.get('id') or 0)
    user_id = int(data.get('user_id', 0))
    sales_rep_name = str(data.get('sales_rep_name', '')).strip()
    task_basis = str(data.get('task_basis', '')).strip()
    doctor_name = str(data.get('doctor_name', '')).strip()
    clinic_name = str(data.get('clinic_name', '')).strip()
    task_category = str(data.get('task_category', '')).strip()
    area = str(data.get('area', '')).strip()
    source_lat = float(data.get('source_lat', 0))
    source_lng = float(data.get('source_lng', 0))
    clinic_lat = float(data.get('clinic_lat', 0))
    clinic_lng = float(data.get('clinic_lng', 0))
    clinic_address = str(data.get('clinic_address', '')).strip()
    notes = str(data.get('notes', '')).strip()

    if user_id < 0 or not task_basis or not doctor_name or not clinic_name:
        return jsonify({"success": False, "message": "Missing required fields."}), 200

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            if task_id > 0:
                cursor.execute(
                    """UPDATE tasks 
                       SET user_id = %s, sales_rep_name = %s, task_basis = %s, doctor_name = %s, clinic_name = %s, task_category = %s, area = %s, source_lat = %s, source_lng = %s, clinic_lat = %s, clinic_lng = %s, clinic_address = %s, notes = %s
                       WHERE id = %s""",
                    (user_id, sales_rep_name, task_basis, doctor_name, clinic_name, task_category, area, source_lat, source_lng, clinic_lat, clinic_lng, clinic_address, notes, task_id)
                )
                res_id = task_id
                msg = "Task updated!"
            else:
                cursor.execute(
                    """INSERT INTO tasks 
                       (user_id, sales_rep_name, task_basis, doctor_name, clinic_name, task_category, area, source_lat, source_lng, clinic_lat, clinic_lng, clinic_address, notes, status)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'pending')""",
                    (user_id, sales_rep_name, task_basis, doctor_name, clinic_name, task_category, area, source_lat, source_lng, clinic_lat, clinic_lng, clinic_address, notes)
                )
                res_id = cursor.lastrowid
                msg = "Task saved!"
        conn.close()

        return jsonify({"success": True, "message": msg, "task_id": res_id}), 200
    except Exception as e:
        return jsonify({"success": False, "message": f"Failed to save task: {str(e)}"}), 200

def haversine_distance_meters(lat1, lon1, lat2, lon2):
    import math
    earth_radius = 6371000.0
    d_lat = math.radians(lat2 - lat1)
    d_lon = math.radians(lon2 - lon1)
    a = (math.sin(d_lat / 2.0) ** 2 +
         math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) *
         math.sin(d_lon / 2.0) ** 2)
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
    return earth_radius * c

# ───────────────────────────────────────────────────────────────────────────────
# 7. UPDATE TASK STATUS
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/update_task_status.php', methods=['POST', 'OPTIONS'])
@app.route('/update_task_status', methods=['POST', 'OPTIONS'])
def update_task_status():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    data = request.get_json(silent=True) or {}
    task_id = int(data.get('task_id', 0))
    status = str(data.get('status', 'completed')).strip().lower()
    checkout_type = str(data.get('checkout_type', 'MANUAL')).strip()
    checkout_lat = data.get('checkout_lat') if data.get('checkout_lat') is not None else data.get('lat')
    checkout_lng = data.get('checkout_lng') if data.get('checkout_lng') is not None else data.get('lng')
    dest_lat = data.get('destination_lat')
    dest_lng = data.get('destination_lng')

    if not task_id:
        return jsonify({"success": False, "message": "task_id is required."}), 200

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute("SELECT * FROM tasks WHERE id = %s", (task_id,))
            task = cursor.fetchone()
            if not task:
                conn.close()
                return jsonify({"success": False, "message": f"Task #{task_id} not found."}), 200

            if task.get('status') == 'completed':
                conn.close()
                return jsonify({
                    "success": True,
                    "already_completed": True,
                    "message": "Task is already completed.",
                    "task_id": task_id,
                    "status": "completed"
                }), 200

            distance_meters = None
            if status == 'completed':
                if dest_lat is None and task.get('clinic_lat') is not None:
                    dest_lat = float(task['clinic_lat'])
                if dest_lng is None and task.get('clinic_lng') is not None:
                    dest_lng = float(task['clinic_lng'])

                if checkout_lat is None or checkout_lng is None or dest_lat is None or dest_lng is None:
                    conn.close()
                    return jsonify({
                        "success": False,
                        "message": "You are not in the Doctor's Clinic. Valid checkout coordinates and destination coordinates are required."
                    }), 200

                checkout_lat = float(checkout_lat)
                checkout_lng = float(checkout_lng)
                dest_lat = float(dest_lat)
                dest_lng = float(dest_lng)

                if checkout_lat == 0.0 or dest_lat == 0.0:
                    conn.close()
                    return jsonify({
                        "success": False,
                        "message": "You are not in the Doctor's Clinic. Valid checkout coordinates and destination coordinates are required."
                    }), 200

                dist = haversine_distance_meters(checkout_lat, checkout_lng, dest_lat, dest_lng)
                distance_meters = round(dist, 2)

                # Strict 15.0-meter radius validation (15.0m or less allowed; 15.01m or more blocked)
                if distance_meters > 15.0:
                    conn.close()
                    return jsonify({
                        "success": False,
                        "message": f"You are not in the Doctor's Clinic. Location ({distance_meters}m) is outside the 15-meter destination radius.",
                        "distance_meters": distance_meters,
                        "required_radius": 15.0
                    }), 200

            now_dt = datetime.datetime.now()
            checkout_date = data.get('checkout_date', now_dt.strftime('%Y-%m-%d'))
            checkout_time = data.get('checkout_time', now_dt.strftime('%H:%M:%S'))
            checkout_datetime = data.get('checkout_datetime', now_dt.strftime('%Y-%m-%d %H:%M:%S'))
            stable_sec = int(data.get('stable_duration_seconds', 60 if checkout_type.upper() == 'AUTO' else 0))

            dest_reached_at = task.get('destination_reached_at')
            target_deadline_at = task.get('target_deadline_at')
            if not dest_reached_at and status == 'completed':
                dest_reached_at = now_dt
                target_deadline_at = now_dt + datetime.timedelta(seconds=300)

            overtime_reason = str(data.get('overtime_reason', '')).strip()
            completion_result = 'within_target'
            overtime_sec = 0

            if target_deadline_at:
                if isinstance(target_deadline_at, str):
                    try:
                        target_deadline_dt = datetime.datetime.fromisoformat(target_deadline_at)
                    except Exception:
                        target_deadline_dt = now_dt
                else:
                    target_deadline_dt = target_deadline_at

                if now_dt > target_deadline_dt:
                    if not overtime_reason:
                        conn.close()
                        return jsonify({
                            "success": False,
                            "overtime_reason_required": True,
                            "message": "5-minute destination target exceeded. Please provide reason for overtime.",
                            "distance_meters": distance_meters,
                            "destination_reached_at": format_datetime(dest_reached_at),
                            "target_deadline_at": format_datetime(target_deadline_dt),
                            "overtime_seconds": int((now_dt - target_deadline_dt).total_seconds())
                        }), 200
                    completion_result = 'overtime'
                    overtime_sec = max(0, int((now_dt - target_deadline_dt).total_seconds()))

            cursor.execute("""
                UPDATE tasks SET
                    status = %s,
                    checked_out_at = %s,
                    checkout_date = %s,
                    checkout_time = %s,
                    checkout_type = %s,
                    checkout_lat = %s,
                    checkout_lng = %s,
                    destination_distance_meters = %s,
                    final_distance_meters = %s,
                    final_lat = %s,
                    final_lng = %s,
                    stable_duration_seconds = %s,
                    destination_reached_at = COALESCE(destination_reached_at, %s),
                    target_deadline_at = COALESCE(target_deadline_at, %s),
                    target_duration_seconds = 300,
                    is_inside_destination = 1,
                    completion_result = %s,
                    overtime_duration_seconds = %s,
                    overtime_reason = %s,
                    last_latitude = %s,
                    last_longitude = %s,
                    last_location_update = NOW(),
                    updated_at = NOW()
                WHERE id = %s
            """, (
                status,
                checkout_datetime,
                checkout_date,
                checkout_time,
                checkout_type,
                checkout_lat,
                checkout_lng,
                distance_meters,
                distance_meters,
                checkout_lat,
                checkout_lng,
                stable_sec,
                dest_reached_at,
                target_deadline_at,
                completion_result,
                overtime_sec,
                overtime_reason,
                checkout_lat,
                checkout_lng,
                task_id
            ))
            conn.commit()
        conn.close()

        return jsonify({
            "success": True,
            "message": "Task status updated!",
            "task_id": task_id,
            "status": status,
            "distance_meters": distance_meters,
            "final_distance_meters": distance_meters,
            "completion_result": completion_result,
            "destination_reached_at": format_datetime(dest_reached_at),
            "target_deadline_at": format_datetime(target_deadline_at),
            "overtime_duration_seconds": overtime_sec
        }), 200
    except Exception as e:
        return jsonify({"success": False, "message": f"Failed to update task status: {str(e)}"}), 200

# ───────────────────────────────────────────────────────────────────────────────
# 7B. PUSH LOCATION & DESTINATION MONITORING
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/push_location.php', methods=['POST', 'OPTIONS'])
@app.route('/push_location', methods=['POST', 'OPTIONS'])
def push_location():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    data = request.get_json(silent=True) or {}
    user_id = int(data.get('user_id', 0))
    task_id = int(data.get('task_id', 0))
    sales_rep_name = str(data.get('sales_rep_name', '')).strip()
    lat = data.get('lat')
    lng = data.get('lng')

    if user_id <= 0 or task_id <= 0 or lat is None or lng is None:
        return jsonify({"success": False, "message": "Invalid parameters."}), 200

    lat = float(lat)
    lng = float(lng)

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute("SELECT * FROM tasks WHERE id = %s AND user_id = %s", (task_id, user_id))
            task = cursor.fetchone()
            if not task:
                conn.close()
                return jsonify({"success": False, "message": f"Task #{task_id} not found."}), 200

            if task.get('status') != 'in_progress':
                conn.close()
                return jsonify({"success": False, "message": "Task is not in progress."}), 200

            clinic_lat = float(task.get('clinic_lat') or 0)
            clinic_lng = float(task.get('clinic_lng') or 0)
            distance_meters = None
            is_inside = False

            if clinic_lat != 0.0 and clinic_lng != 0.0:
                dist = haversine_distance_meters(lat, lng, clinic_lat, clinic_lng)
                distance_meters = round(dist, 2)
                # Strict 15.0m threshold (<= 15.0m allowed, >= 15.01m outside)
                is_inside = (distance_meters <= 15.0)

            now_dt = datetime.datetime.now()
            dest_reached_at = task.get('destination_reached_at')
            target_deadline_at = task.get('target_deadline_at')
            target_duration_sec = int(task.get('target_duration_seconds') or 300)
            inside_sec = int(task.get('time_inside_destination_seconds') or 0)
            just_reached = False

            if is_inside:
                if not dest_reached_at:
                    dest_reached_at = now_dt
                    target_deadline_at = now_dt + datetime.timedelta(seconds=300)
                    just_reached = True
                    inside_sec = 1
                else:
                    inside_sec += 1

            if just_reached:
                cursor.execute("""
                    UPDATE tasks SET
                        last_latitude = %s,
                        last_longitude = %s,
                        last_location_update = NOW(),
                        last_destination_distance_meters = %s,
                        is_inside_destination = 1,
                        time_inside_destination_seconds = %s,
                        destination_reached_at = %s,
                        target_deadline_at = %s,
                        target_duration_seconds = 300,
                        destination_reached_lat = %s,
                        destination_reached_lng = %s,
                        destination_reached_distance_meters = %s
                    WHERE id = %s
                """, (lat, lng, distance_meters, inside_sec, dest_reached_at, target_deadline_at, lat, lng, distance_meters, task_id))
            else:
                cursor.execute("""
                    UPDATE tasks SET
                        last_latitude = %s,
                        last_longitude = %s,
                        last_location_update = NOW(),
                        last_destination_distance_meters = %s,
                        is_inside_destination = %s,
                        time_inside_destination_seconds = %s
                    WHERE id = %s
                """, (lat, lng, distance_meters, 1 if is_inside else 0, inside_sec, task_id))

            conn.commit()
        conn.close()

        is_overtime = False
        remaining_seconds = None
        overtime_seconds = 0

        if target_deadline_at:
            if isinstance(target_deadline_at, str):
                try:
                    td_dt = datetime.datetime.fromisoformat(target_deadline_at)
                except Exception:
                    td_dt = now_dt
            else:
                td_dt = target_deadline_at
            diff = (td_dt - now_dt).total_seconds()
            if diff >= 0:
                remaining_seconds = int(diff)
            else:
                is_overtime = True
                remaining_seconds = 0
                overtime_seconds = int(abs(diff))

        return jsonify({
            "success": True,
            "message": "Tracking location recorded.",
            "task_id": task_id,
            "distance_meters": distance_meters,
            "is_inside_destination": is_inside,
            "destination_reached": dest_reached_at is not None,
            "destination_reached_at": format_datetime(dest_reached_at),
            "target_deadline_at": format_datetime(target_deadline_at),
            "target_duration_seconds": target_duration_sec,
            "time_inside_destination_seconds": inside_sec,
            "is_overtime": is_overtime,
            "remaining_seconds": remaining_seconds,
            "overtime_seconds": overtime_seconds
        }), 200
    except Exception as e:
        return jsonify({"success": False, "message": f"Push location error: {str(e)}"}), 200


# ───────────────────────────────────────────────────────────────────────────────
# 8. GET ROUTE (OSRM PROXY)
# ───────────────────────────────────────────────────────────────────────────────

def decode_polyline(encoded):
    length = len(encoded)
    index = 0
    points = []
    lat = 0
    lng = 0
    while index < length:
        b = 0
        shift = 0
        result = 0
        while True:
            b = ord(encoded[index]) - 63
            index += 1
            result |= (b & 0x1f) << shift
            shift += 5
            if b < 0x20:
                break
        dlat = ~(result >> 1) if (result & 1) else (result >> 1)
        lat += dlat

        shift = 0
        result = 0
        while True:
            b = ord(encoded[index]) - 63
            index += 1
            result |= (b & 0x1f) << shift
            shift += 5
            if b < 0x20:
                break
        dlng = ~(result >> 1) if (result & 1) else (result >> 1)
        lng += dlng

        points.append([lng / 1e5, lat / 1e5])
    return points

@app.route('/backend/get_route.php', methods=['GET', 'OPTIONS'])
@app.route('/get_route', methods=['GET', 'OPTIONS'])
def get_route():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    src_lat = request.args.get('src_lat', 0.0, type=float)
    src_lng = request.args.get('src_lng', 0.0, type=float)
    dest_lat = request.args.get('dest_lat', 0.0, type=float)
    dest_lng = request.args.get('dest_lng', 0.0, type=float)

    if not src_lat or not src_lng or not dest_lat or not dest_lng:
        return jsonify({"success": False, "message": "Coordinates required."}), 200

    urls = [
        f"https://router.project-osrm.org/route/v1/driving/{src_lng},{src_lat};{dest_lng},{dest_lat}?overview=full&geometries=polyline",
        f"https://routing.openstreetmap.de/routed-car/route/v1/driving/{src_lng},{src_lat};{dest_lng},{dest_lat}?overview=full&geometries=polyline",
        f"https://router.project-osrm.org/route/v1/driving/{src_lng},{src_lat};{dest_lng},{dest_lat}?overview=full&geometries=geojson",
        f"https://routing.openstreetmap.de/routed-car/route/v1/driving/{src_lng},{src_lat};{dest_lng},{dest_lat}?overview=full&geometries=geojson"
    ]

    headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Accept: application/json"}

    for osrm_url in urls:
        try:
            resp = requests.get(osrm_url, headers=headers, timeout=8, verify=False)
            if resp.status_code == 200:
                data = resp.json()
                if data.get('code') == 'Ok' and data.get('routes'):
                    route = data['routes'][0]
                    distance = route.get('distance', 0)
                    geometry = route.get('geometry')

                    if isinstance(geometry, str):
                        points = decode_polyline(geometry)
                    elif isinstance(geometry, dict) and 'coordinates' in geometry:
                        points = geometry['coordinates']
                    else:
                        continue

                    if points:
                        return jsonify({
                            "success": True,
                            "is_road_route": True,
                            "points": points,
                            "distance": distance
                        }), 200
        except Exception:
            continue

    return jsonify({"success": False, "message": "Could not resolve road route."}), 200

# ───────────────────────────────────────────────────────────────────────────────
# 9. GET ALL SALES REPS
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/get_all_sales_reps.php', methods=['GET', 'OPTIONS'])
@app.route('/get_all_sales_reps', methods=['GET', 'OPTIONS'])
def get_all_sales_reps():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute("SELECT id, name, email, phone, role, created_at FROM users WHERE role = 'sales_rep' ORDER BY id ASC")
            reps_db = cursor.fetchall()

            reps = []
            now_ts = time.time()
            for r in reps_db:
                user_id = int(r['id'])
                cursor.execute(
                    "SELECT type, lat, lng, created_at FROM attendance_history WHERE user_id = %s ORDER BY id DESC LIMIT 1",
                    (user_id,)
                )
                att = cursor.fetchone()

                last_lat = None
                last_lng = None
                last_ping_at = None
                is_online = False

                if att:
                    last_lat = float(att['lat'])
                    last_lng = float(att['lng'])
                    ping_dt = att['created_at']
                    last_ping_at = format_datetime(ping_dt)
                    att_type = str(att.get('type', '')).strip().lower()
                    is_online = (att_type == 'check_in')

                reps.append({
                    "id": user_id,
                    "name": r['name'],
                    "email": r['email'],
                    "phone": r['phone'],
                    "is_active": True,
                    "created_at": format_datetime(r['created_at']),
                    "last_lat": last_lat,
                    "last_lng": last_lng,
                    "last_accuracy": 10.0,
                    "last_ping_at": last_ping_at,
                    "is_online": is_online
                })
        conn.close()

        return jsonify({"success": True, "count": len(reps), "reps": reps}), 200
    except Exception as e:
        return jsonify({"success": False, "message": f"DB error: {str(e)}"}), 200

# ───────────────────────────────────────────────────────────────────────────────
# 10. GET ATTENDANCE HISTORY
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/get_attendance_history.php', methods=['GET', 'OPTIONS'])
@app.route('/get_attendance_history', methods=['GET', 'OPTIONS'])
def get_attendance_history():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    user_id = request.args.get('user_id', 0, type=int)
    att_type = request.args.get('type', '').strip()
    date_str = request.args.get('date', '').strip()

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            where_clauses = ["1=1"]
            params = []

            if user_id > 0:
                where_clauses.append("user_id = %s")
                params.append(user_id)
            if att_type in ['check_in', 'check_out']:
                where_clauses.append("type = %s")
                params.append(att_type)
            if date_str:
                where_clauses.append("DATE(created_at) = %s")
                params.append(date_str)

            sql = f"SELECT id, user_id, sales_rep_name, type, lat, lng, address, notes, created_at FROM attendance_history WHERE {' AND '.join(where_clauses)} ORDER BY created_at DESC"
            cursor.execute(sql, tuple(params))
            rows = cursor.fetchall()
        conn.close()

        history = [
            {
                "id": int(r['id']),
                "user_id": int(r['user_id']),
                "sales_rep_name": str(r['sales_rep_name']),
                "type": str(r['type']),
                "lat": float(r['lat']),
                "lng": float(r['lng']),
                "address": str(r.get('address') or ''),
                "notes": str(r.get('notes') or ''),
                "created_at": format_datetime(r['created_at'])
            }
            for r in rows
        ]

        return jsonify({"success": True, "count": len(history), "history": history}), 200
    except Exception as e:
        return jsonify({"success": False, "message": f"DB error: {str(e)}"}), 200

# ───────────────────────────────────────────────────────────────────────────────
# 11. SAVE ATTENDANCE
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/save_attendance.php', methods=['POST', 'OPTIONS'])
@app.route('/save_attendance', methods=['POST', 'OPTIONS'])
def save_attendance():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    data = request.get_json(silent=True) or {}
    user_id = int(data.get('user_id', 0))
    sales_rep_name = str(data.get('sales_rep_name', '')).strip()
    att_type = str(data.get('type', '')).strip()
    lat = float(data.get('lat', 0.0))
    lng = float(data.get('lng', 0.0))
    address = str(data.get('address', '')).strip()
    notes = str(data.get('notes', '')).strip()

    if user_id <= 0:
        return jsonify({"success": False, "message": f"Invalid user_id: {user_id}"}), 200
    if not sales_rep_name:
        return jsonify({"success": False, "message": "sales_rep_name is required"}), 200
    if att_type not in ['check_in', 'check_out']:
        return jsonify({"success": False, "message": f"type must be check_in or check_out, got: {att_type}"}), 200
    if lat == 0 and lng == 0:
        return jsonify({"success": False, "message": "Valid lat/lng required"}), 200

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute(
                """INSERT INTO attendance_history (user_id, sales_rep_name, type, lat, lng, address, notes)
                   VALUES (%s, %s, %s, %s, %s, %s, %s)""",
                (user_id, sales_rep_name, att_type, lat, lng, address, notes)
            )
            record_id = cursor.lastrowid
        conn.close()

        return jsonify({
            "success": True,
            "message": "Attendance saved successfully",
            "record_id": record_id,
            "type": att_type,
            "lat": lat,
            "lng": lng,
            "saved_at": datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        }), 200
    except Exception as e:
        return jsonify({"success": False, "message": f"DB error: {str(e)}"}), 200

# ───────────────────────────────────────────────────────────────────────────────
# 12. SAVE ORDER PDF
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/save_order_pdf.php', methods=['POST', 'OPTIONS'])
@app.route('/save_order_pdf', methods=['POST', 'OPTIONS'])
def save_order_pdf():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    data = request.get_json(silent=True) or {}
    user_id = int(data.get('user_id', 0))
    doctor_name = str(data.get('doctor_name', '')).strip()
    products_json = data.get('products_json', '[]')
    if isinstance(products_json, (dict, list)):
        products_json = json.dumps(products_json)
    pdf_filename = str(data.get('pdf_filename', '')).strip()

    if not user_id or not doctor_name or not pdf_filename:
        return jsonify({"success": False, "message": "Missing required fields."}), 200

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute(
                "INSERT INTO order_pdfs (user_id, doctor_name, products_json, pdf_filename) VALUES (%s, %s, %s, %s)",
                (user_id, doctor_name, products_json, pdf_filename)
            )
            rec_id = cursor.lastrowid
        conn.close()

        return jsonify({"success": True, "message": "Order PDF saved!", "id": rec_id}), 200
    except Exception as e:
        return jsonify({"success": False, "message": f"Failed: {str(e)}"}), 200

# ───────────────────────────────────────────────────────────────────────────────
# 13. GET LIVE LOCATIONS
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/get_live_locations.php', methods=['GET', 'OPTIONS'])
@app.route('/get_live_locations', methods=['GET', 'OPTIONS'])
def get_live_locations():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            sql = """SELECT u.id as user_id, u.name as sales_rep_name, ah.type, ah.lat, ah.lng, ah.created_at as recorded_at
                    FROM users u
                    INNER JOIN (
                        SELECT user_id, MAX(id) as max_id
                        FROM attendance_history
                        GROUP BY user_id
                    ) latest ON u.id = latest.user_id
                    INNER JOIN attendance_history ah ON latest.max_id = ah.id
                    WHERE u.role = 'sales_rep'"""
            cursor.execute(sql)
            rows = cursor.fetchall()
        conn.close()

        reps = [
            {
                "user_id": int(r['user_id']),
                "sales_rep_name": r['sales_rep_name'],
                "type": r.get('type', 'check_in'),
                "lat": float(r['lat']),
                "lng": float(r['lng']),
                "accuracy": 10.0,
                "recorded_at": format_datetime(r['recorded_at'])
            }
            for r in rows
        ]

        return jsonify({"success": True, "reps": reps}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 200

# ───────────────────────────────────────────────────────────────────────────────
# 14. ADD DOCTOR
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/add_doctor.php', methods=['POST', 'OPTIONS'])
@app.route('/add_doctor', methods=['POST', 'OPTIONS'])
def add_doctor():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    data = request.get_json(silent=True) or {}
    name = str(data.get('name', '')).strip()
    speciality = str(data.get('speciality', '')).strip()
    phone = str(data.get('phone', '')).strip()
    area = str(data.get('area', '')).strip()
    added_by = int(data.get('added_by', 0))

    if not name:
        return jsonify({"success": False, "message": "Doctor name is required."}), 200

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute("INSERT INTO doctors (name, speciality, phone, area, added_by, is_deleted) VALUES (%s, %s, %s, %s, %s, 0)", (name, speciality or 'General Physician', phone, area, added_by))
            doc_id = cursor.lastrowid
        conn.close()

        return jsonify({
            "success": True,
            "message": "Doctor added!",
            "doctor": {"id": doc_id, "name": name, "speciality": speciality, "phone": phone, "area": area, "added_by": added_by}
        }), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 200

# ───────────────────────────────────────────────────────────────────────────────
# 15. ADD CLINIC
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/add_clinic.php', methods=['POST', 'OPTIONS'])
@app.route('/add_clinic', methods=['POST', 'OPTIONS'])
def add_clinic():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    data = request.get_json(silent=True) or {}
    name = str(data.get('name', '')).strip()
    address = str(data.get('address', '')).strip()
    phone = str(data.get('phone', '')).strip()
    map_url = str(data.get('map_url', '')).strip()
    lat = float(data.get('lat', 0.0))
    lng = float(data.get('lng', 0.0))
    area = str(data.get('area', '')).strip()
    added_by = int(data.get('added_by', 0))

    if not name or lat == 0 or lng == 0:
        return jsonify({"success": False, "message": "Name and valid coordinates required."}), 200

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute(
                "INSERT INTO clinics (name, lat, lng, address, phone, map_url, area, added_by, is_deleted) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, 0)",
                (name, lat, lng, address, phone, map_url, area, added_by)
            )
            clinic_id = cursor.lastrowid
        conn.close()

        return jsonify({
            "success": True,
            "message": "Clinic added!",
            "clinic": {"id": clinic_id, "name": name, "lat": lat, "lng": lng, "address": address, "phone": phone, "map_url": map_url, "area": area, "added_by": added_by}
        }), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 200

# ───────────────────────────────────────────────────────────────────────────────
# 15A. ADD AREA / DIVISION
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/add_area.php', methods=['POST', 'OPTIONS'])
@app.route('/add_area', methods=['POST', 'OPTIONS'])
def add_area():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    data = request.get_json(silent=True) or {}
    name = str(data.get('name', '') or data.get('area', '')).strip()
    added_by = int(data.get('added_by', 0))

    if not name or name.lower() == 'all areas':
        return jsonify({"success": False, "message": "Valid Area / Division name is required."}), 200

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute("CREATE TABLE IF NOT EXISTS areas (id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY, name VARCHAR(100) NOT NULL UNIQUE, added_by INT UNSIGNED NOT NULL DEFAULT 0, created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP)")
            cursor.execute("CREATE TABLE IF NOT EXISTS deleted_areas (id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY, area VARCHAR(100) NOT NULL UNIQUE, deleted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP)")
            cursor.execute("DELETE FROM deleted_areas WHERE LOWER(area) = LOWER(%s)", (name,))
            cursor.execute("INSERT INTO areas (name, added_by) VALUES (%s, %s) ON DUPLICATE KEY UPDATE added_by = VALUES(added_by)", (name, added_by))
        conn.close()

        return jsonify({
            "success": True,
            "message": "Area added successfully!",
            "area": name
        }), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 200

# ───────────────────────────────────────────────────────────────────────────────
# 15B. DELETE DOCTOR / CLINIC (Soft Delete with Ownership & Permission Validation)
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/delete_doctor_clinic.php', methods=['POST', 'OPTIONS'])
@app.route('/delete_doctor_clinic', methods=['POST', 'OPTIONS'])
def delete_doctor_clinic():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    data = request.get_json(silent=True) or {}
    user_id = int(data.get('user_id', 0))
    role = str(data.get('role', 'sales_rep')).strip()
    doctor_ids = data.get('doctor_ids', [])
    clinic_ids = data.get('clinic_ids', [])

    if not doctor_ids and not clinic_ids:
        return jsonify({"success": False, "message": "No records selected for deletion."}), 200

    try:
        conn = get_db_connection()
        deleted_doctor_ids = []
        deleted_clinic_ids = []

        with conn.cursor() as cursor:
            # Soft delete doctors
            for doc_id in doctor_ids:
                try:
                    d_id = int(doc_id)
                    if role == 'admin':
                        cursor.execute("UPDATE doctors SET is_deleted = 1, deleted_at = NOW() WHERE id = %s", (d_id,))
                    else:
                        cursor.execute("UPDATE doctors SET is_deleted = 1, deleted_at = NOW() WHERE id = %s AND (added_by = %s OR added_by = 0 OR added_by IS NULL)", (d_id, user_id))
                    if cursor.rowcount > 0:
                        deleted_doctor_ids.append(d_id)
                except Exception:
                    pass

            # Soft delete clinics
            for clin_id in clinic_ids:
                try:
                    c_id = int(clin_id)
                    if role == 'admin':
                        cursor.execute("UPDATE clinics SET is_deleted = 1, deleted_at = NOW() WHERE id = %s", (c_id,))
                    else:
                        cursor.execute("UPDATE clinics SET is_deleted = 1, deleted_at = NOW() WHERE id = %s AND (added_by = %s OR added_by = 0 OR added_by IS NULL)", (c_id, user_id))
                    if cursor.rowcount > 0:
                        deleted_clinic_ids.append(c_id)
                except Exception:
                    pass

        conn.close()
        total = len(deleted_doctor_ids) + len(deleted_clinic_ids)
        return jsonify({
            "success": True,
            "message": f"{total} record{'s' if total != 1 else ''} deleted successfully.",
            "deleted_doctor_ids": deleted_doctor_ids,
            "deleted_clinic_ids": deleted_clinic_ids
        }), 200
    except Exception as e:
        return jsonify({"success": False, "message": f"Failed to delete records: {str(e)}"}), 200

# ───────────────────────────────────────────────────────────────────────────────
# 15C. RESTORE DOCTOR / CLINIC (Undo Deletion)
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/restore_doctor_clinic.php', methods=['POST', 'OPTIONS'])
@app.route('/restore_doctor_clinic', methods=['POST', 'OPTIONS'])
def restore_doctor_clinic():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    data = request.get_json(silent=True) or {}
    user_id = int(data.get('user_id', 0))
    role = str(data.get('role', 'sales_rep')).strip()
    doctor_ids = data.get('doctor_ids', [])
    clinic_ids = data.get('clinic_ids', [])

    if not doctor_ids and not clinic_ids:
        return jsonify({"success": False, "message": "No records specified to restore."}), 200

    try:
        conn = get_db_connection()
        restored_doctor_ids = []
        restored_clinic_ids = []

        with conn.cursor() as cursor:
            for doc_id in doctor_ids:
                try:
                    d_id = int(doc_id)
                    if role == 'admin':
                        cursor.execute("UPDATE doctors SET is_deleted = 0, deleted_at = NULL WHERE id = %s", (d_id,))
                    else:
                        cursor.execute("UPDATE doctors SET is_deleted = 0, deleted_at = NULL WHERE id = %s AND (added_by = %s OR added_by = 0 OR added_by IS NULL)", (d_id, user_id))
                    if cursor.rowcount > 0:
                        restored_doctor_ids.append(d_id)
                except Exception:
                    pass

            for clin_id in clinic_ids:
                try:
                    c_id = int(clin_id)
                    if role == 'admin':
                        cursor.execute("UPDATE clinics SET is_deleted = 0, deleted_at = NULL WHERE id = %s", (c_id,))
                    else:
                        cursor.execute("UPDATE clinics SET is_deleted = 0, deleted_at = NULL WHERE id = %s AND (added_by = %s OR added_by = 0 OR added_by IS NULL)", (c_id, user_id))
                    if cursor.rowcount > 0:
                        restored_clinic_ids.append(c_id)
                except Exception:
                    pass

        conn.close()
        total = len(restored_doctor_ids) + len(restored_clinic_ids)
        return jsonify({
            "success": True,
            "message": f"{total} record{'s' if total != 1 else ''} restored successfully.",
            "restored_doctor_ids": restored_doctor_ids,
            "restored_clinic_ids": restored_clinic_ids
        }), 200
    except Exception as e:
        return jsonify({"success": False, "message": f"Failed to restore records: {str(e)}"}), 200

# ───────────────────────────────────────────────────────────────────────────────
# 16. RESOLVE MAP URL
def _extract_coords_from_string(text):
    if not text:
        return None

    # 1. PRIORITY 1: Exact Google Maps Place / Dropped Pin (!3d<lat>!4d<lng> or !4d<lng>!3d<lat>)
    m3d = re.search(r'!3d(-?\d+\.\d+).*?!4d(-?\d+\.\d+)', text, re.DOTALL)
    if m3d:
        try:
            lat, lng = float(m3d.group(1)), float(m3d.group(2))
            if -90 <= lat <= 90 and -180 <= lng <= 180 and (lat != 0 or lng != 0):
                return lat, lng
        except Exception:
            pass

    m4d = re.search(r'!4d(-?\d+\.\d+).*?!3d(-?\d+\.\d+)', text, re.DOTALL)
    if m4d:
        try:
            lat, lng = float(m4d.group(2)), float(m4d.group(1))
            if -90 <= lat <= 90 and -180 <= lng <= 180 and (lat != 0 or lng != 0):
                return lat, lng
        except Exception:
            pass

    # 2. PRIORITY 2: Explicit Target Location / Destination / Query / Pinned coords
    md = re.search(r'[?&](?:destination|daddr)=(-?\d+\.\d+)[,+](-?\d+\.\d+)', text, re.IGNORECASE)
    if md:
        try:
            lat, lng = float(md.group(1)), float(md.group(2))
            if -90 <= lat <= 90 and -180 <= lng <= 180 and (lat != 0 or lng != 0):
                return lat, lng
        except Exception:
            pass

    mq = re.search(r'[?&](?:q|query|loc|ll|saddr)=(?:loc:)?(-?\d+\.\d+)[,+](-?\d+\.\d+)', text, re.IGNORECASE)
    if mq:
        try:
            lat, lng = float(mq.group(1)), float(mq.group(2))
            if -90 <= lat <= 90 and -180 <= lng <= 180 and (lat != 0 or lng != 0):
                return lat, lng
        except Exception:
            pass

    # 3. PRIORITY 3: geo: URI
    mg = re.search(r'geo:(-?\d+\.\d+),(-?\d+\.\d+)', text, re.IGNORECASE)
    if mg:
        try:
            lat, lng = float(mg.group(1)), float(mg.group(2))
            if -90 <= lat <= 90 and -180 <= lng <= 180 and (lat != 0 or lng != 0):
                return lat, lng
        except Exception:
            pass

    # 4. PRIORITY 4: Static map marker or OpenGraph marker coordinates
    mm = re.search(r'markers=(?:[^&]*?(?:%7C|\|))?(-?\d+\.\d+)(?:%2C|,)(-?\d+\.\d+)', text, re.IGNORECASE)
    if mm:
        try:
            lat, lng = float(mm.group(1)), float(mm.group(2))
            if -90 <= lat <= 90 and -180 <= lng <= 180 and (lat != 0 or lng != 0):
                return lat, lng
        except Exception:
            pass

    # Schema.org meta
    mlat = re.search(r'itemprop="latitude"[^>]*content="(-?\d+\.\d+)"', text, re.IGNORECASE)
    mlng = re.search(r'itemprop="longitude"[^>]*content="(-?\d+\.\d+)"', text, re.IGNORECASE)
    if mlat and mlng:
        try:
            lat, lng = float(mlat.group(1)), float(mlng.group(1))
            if -90 <= lat <= 90 and -180 <= lng <= 180 and (lat != 0 or lng != 0):
                return lat, lng
        except Exception:
            pass

    # APP_INITIALIZATION_STATE or js array
    mapp = re.search(r'window\.APP_INITIALIZATION_STATE\s*=\s*\[\[\[(-?\d+\.\d+),(-?\d+\.\d+)\]', text)
    if mapp:
        try:
            lat, lng = float(mapp.group(1)), float(mapp.group(2))
            if -90 <= lat <= 90 and -180 <= lng <= 180 and (lat != 0 or lng != 0):
                return lat, lng
        except Exception:
            pass

    marr = re.search(r'\[null,null,(-?\d+\.\d{3,}),(-?\d+\.\d{3,})\]', text)
    if marr:
        try:
            lat, lng = float(marr.group(1)), float(marr.group(2))
            if -90 <= lat <= 90 and -180 <= lng <= 180 and (lat != 0 or lng != 0):
                return lat, lng
        except Exception:
            pass

    # 5. PRIORITY 5: Viewport / Camera Coordinates (@lat,lng)
    m = re.search(r'@(-?\d+\.\d+),(-?\d+\.\d+)', text)
    if m:
        try:
            lat, lng = float(m.group(1)), float(m.group(2))
            if -90 <= lat <= 90 and -180 <= lng <= 180 and (lat != 0 or lng != 0):
                return lat, lng
        except Exception:
            pass

    # staticmap center fallback
    ms = re.search(r'staticmap\?[^"]*center=(-?\d+\.\d+)(?:%2C|,)(-?\d+\.\d+)', text, re.IGNORECASE)
    if ms:
        try:
            lat, lng = float(ms.group(1)), float(ms.group(2))
            if -90 <= lat <= 90 and -180 <= lng <= 180 and (lat != 0 or lng != 0):
                return lat, lng
        except Exception:
            pass

    # 6. PRIORITY 6: Plain coordinates e.g. "13.0827, 80.2707"
    mp = re.search(r'^\s*\(?\s*(-?\d{1,3}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)\s*\)?\s*$', text)
    if mp:
        try:
            lat, lng = float(mp.group(1)), float(mp.group(2))
            if -90 <= lat <= 90 and -180 <= lng <= 180 and (lat != 0 or lng != 0):
                return lat, lng
        except Exception:
            pass

    return None

@app.route('/backend/resolve_map_url.php', methods=['POST', 'OPTIONS'])
@app.route('/resolve_map_url', methods=['POST', 'OPTIONS'])
def resolve_map_url():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    data = request.get_json(silent=True) or {}
    url = str(data.get('url', '')).strip()
    if not url:
        return jsonify({"success": False, "message": "URL required."}), 200

    # 1. Try direct regex parsing
    coords = _extract_coords_from_string(url)
    if coords:
        return jsonify({"success": True, "lat": coords[0], "lng": coords[1]}), 200

    # 2. Try HTTP request to follow redirects
    try:
        headers = {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
        }
        resp = requests.get(url, headers=headers, allow_redirects=True, timeout=8)
        
        # Check final URL
        coords = _extract_coords_from_string(resp.url)
        if coords:
            return jsonify({"success": True, "lat": coords[0], "lng": coords[1]}), 200

        # Check redirect history URLs
        for hist in resp.history:
            coords = _extract_coords_from_string(hist.url)
            if coords:
                return jsonify({"success": True, "lat": coords[0], "lng": coords[1]}), 200
            loc = hist.headers.get('Location', '')
            if loc:
                coords = _extract_coords_from_string(loc)
                if coords:
                    return jsonify({"success": True, "lat": coords[0], "lng": coords[1]}), 200

        # Check response body text
        if resp.text:
            coords = _extract_coords_from_string(resp.text[:50000])
            if coords:
                return jsonify({"success": True, "lat": coords[0], "lng": coords[1]}), 200
    except Exception:
        pass

    return jsonify({"success": False, "message": "Coordinates not found in URL."}), 200

# ───────────────────────────────────────────────────────────────────────────────
# 17. PUSH LOCATION
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/push_location.php', methods=['POST', 'OPTIONS'])
@app.route('/push_location', methods=['POST', 'OPTIONS'])
def push_location():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    data = request.get_json(silent=True) or {}
    user_id = int(data.get('user_id', 0))
    sales_rep_name = str(data.get('sales_rep_name', '')).strip()
    lat = float(data.get('lat', 0.0))
    lng = float(data.get('lng', 0.0))

    if not user_id or lat == 0 or lng == 0:
        return jsonify({"success": False, "message": "Invalid location payload."}), 200

    try:
        conn = get_db_connection()
        with conn.cursor() as cursor:
            cursor.execute(
                "SELECT type FROM attendance_history WHERE user_id = %s ORDER BY id DESC LIMIT 1",
                (user_id,)
            )
            last_rec = cursor.fetchone()
            if last_rec and str(last_rec.get('type', '')).strip().lower() == 'check_out':
                conn.close()
                return jsonify({"success": True, "message": "User checked out, ping ignored."}), 200

            cursor.execute(
                """INSERT INTO attendance_history (user_id, sales_rep_name, type, lat, lng, address, notes)
                   VALUES (%s, %s, 'check_in', %s, %s, 'Live Ping', 'Automated location push')""",
                (user_id, sales_rep_name or 'Sales Rep', lat, lng)
            )
        conn.close()
        return jsonify({"success": True, "message": "Location updated."}), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 200

# ───────────────────────────────────────────────────────────────────────────────
# 18. DELETE DOCTOR / CLINIC / AREA (SOFT DELETE)
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/delete_doctor_clinic.php', methods=['POST', 'OPTIONS'])
@app.route('/delete_doctor_clinic', methods=['POST', 'OPTIONS'])
def delete_doctor_clinic():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    data = request.get_json(silent=True) or {}
    doctor_ids = data.get('doctor_ids') or []
    clinic_ids = data.get('clinic_ids') or []
    doctor_names = data.get('doctor_names') or []
    clinic_names = data.get('clinic_names') or []
    area_names = data.get('area_names') or []

    if not doctor_ids and not clinic_ids and not doctor_names and not clinic_names and not area_names:
        return jsonify({"success": False, "message": "No records selected for deletion."}), 200

    try:
        conn = get_db_connection()
        deleted_doctor_ids = []
        deleted_clinic_ids = []
        deleted_area_names = []
        with conn.cursor() as cursor:
            cursor.execute("CREATE TABLE IF NOT EXISTS deleted_areas (id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY, area VARCHAR(100) NOT NULL UNIQUE, deleted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP)")
            for a_name in area_names:
                area = str(a_name).strip()
                if not area or area.lower() == 'all areas':
                    continue
                try:
                    cursor.execute("INSERT INTO deleted_areas (area, deleted_at) VALUES (%s, NOW()) ON DUPLICATE KEY UPDATE deleted_at = NOW()", (area,))
                    cursor.execute("UPDATE doctors SET area = '' WHERE area = %s", (area,))
                    cursor.execute("UPDATE clinics SET area = '' WHERE area = %s", (area,))
                    deleted_area_names.append(area)
                except Exception:
                    pass

            for d_id in doctor_ids:
                try:
                    cursor.execute("UPDATE doctors SET is_deleted = 1, deleted_at = NOW() WHERE id = %s", (int(d_id),))
                    if cursor.rowcount > 0:
                        deleted_doctor_ids.append(int(d_id))
                except Exception:
                    pass

            for d_name in doctor_names:
                try:
                    cursor.execute("UPDATE doctors SET is_deleted = 1, deleted_at = NOW() WHERE name = %s AND (is_deleted = 0 OR is_deleted IS NULL)", (str(d_name),))
                except Exception:
                    pass

            for c_id in clinic_ids:
                try:
                    cursor.execute("UPDATE clinics SET is_deleted = 1, deleted_at = NOW() WHERE id = %s", (int(c_id),))
                    if cursor.rowcount > 0:
                        deleted_clinic_ids.append(int(c_id))
                except Exception:
                    pass

            for c_name in clinic_names:
                try:
                    cursor.execute("UPDATE clinics SET is_deleted = 1, deleted_at = NOW() WHERE name = %s AND (is_deleted = 0 OR is_deleted IS NULL)", (str(c_name),))
                except Exception:
                    pass

        conn.close()
        total = max(len(deleted_doctor_ids) + len(deleted_clinic_ids) + len(deleted_area_names), len(doctor_names) + len(clinic_names) + len(area_names))
        return jsonify({
            "success": True,
            "message": f"{total} record{'s' if total != 1 else ''} deleted successfully.",
            "deleted_doctor_ids": deleted_doctor_ids,
            "deleted_clinic_ids": deleted_clinic_ids,
            "deleted_area_names": deleted_area_names
        }), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 200

# ───────────────────────────────────────────────────────────────────────────────
# 19. RESTORE DOCTOR / CLINIC / AREA (UNDO SOFT DELETE)
# ───────────────────────────────────────────────────────────────────────────────
@app.route('/backend/restore_doctor_clinic.php', methods=['POST', 'OPTIONS'])
@app.route('/restore_doctor_clinic', methods=['POST', 'OPTIONS'])
def restore_doctor_clinic():
    if request.method == 'OPTIONS':
        return jsonify({"status": "ok"}), 200

    data = request.get_json(silent=True) or {}
    doctor_ids = data.get('doctor_ids') or []
    clinic_ids = data.get('clinic_ids') or []
    doctor_names = data.get('doctor_names') or []
    clinic_names = data.get('clinic_names') or []
    area_names = data.get('area_names') or []

    if not doctor_ids and not clinic_ids and not doctor_names and not clinic_names and not area_names:
        return jsonify({"success": False, "message": "No records specified to restore."}), 200

    try:
        conn = get_db_connection()
        restored_doctor_ids = []
        restored_clinic_ids = []
        restored_area_names = []
        with conn.cursor() as cursor:
            for a_name in area_names:
                area = str(a_name).strip()
                if not area:
                    continue
                try:
                    cursor.execute("DELETE FROM deleted_areas WHERE area = %s", (area,))
                    restored_area_names.append(area)
                except Exception:
                    pass

            for d_id in doctor_ids:
                try:
                    cursor.execute("UPDATE doctors SET is_deleted = 0, deleted_at = NULL WHERE id = %s", (int(d_id),))
                    if cursor.rowcount > 0:
                        restored_doctor_ids.append(int(d_id))
                except Exception:
                    pass

            for d_name in doctor_names:
                try:
                    cursor.execute("UPDATE doctors SET is_deleted = 0, deleted_at = NULL WHERE name = %s", (str(d_name),))
                except Exception:
                    pass

            for c_id in clinic_ids:
                try:
                    cursor.execute("UPDATE clinics SET is_deleted = 0, deleted_at = NULL WHERE id = %s", (int(c_id),))
                    if cursor.rowcount > 0:
                        restored_clinic_ids.append(int(c_id))
                except Exception:
                    pass

            for c_name in clinic_names:
                try:
                    cursor.execute("UPDATE clinics SET is_deleted = 0, deleted_at = NULL WHERE name = %s", (str(c_name),))
                except Exception:
                    pass

        conn.close()
        total = max(len(restored_doctor_ids) + len(restored_clinic_ids) + len(restored_area_names), len(doctor_names) + len(clinic_names) + len(area_names))
        return jsonify({
            "success": True,
            "message": f"{total} record{'s' if total != 1 else ''} restored successfully.",
            "restored_doctor_ids": restored_doctor_ids,
            "deleted_doctor_ids": restored_doctor_ids,
            "deleted_clinic_ids": restored_clinic_ids,
            "restored_area_names": restored_area_names
        }), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 200
        restored_doctor_ids = []
        restored_clinic_ids = []
        with conn.cursor() as cursor:
            for d_id in doctor_ids:
                try:
                    cursor.execute("UPDATE doctors SET is_deleted = 0, deleted_at = NULL WHERE id = %s", (int(d_id),))
                    if cursor.rowcount > 0:
                        restored_doctor_ids.append(int(d_id))
                except Exception:
                    pass

            for d_name in doctor_names:
                try:
                    cursor.execute("UPDATE doctors SET is_deleted = 0, deleted_at = NULL WHERE name = %s", (str(d_name),))
                except Exception:
                    pass

            for c_id in clinic_ids:
                try:
                    cursor.execute("UPDATE clinics SET is_deleted = 0, deleted_at = NULL WHERE id = %s", (int(c_id),))
                    if cursor.rowcount > 0:
                        restored_clinic_ids.append(int(c_id))
                except Exception:
                    pass

            for c_name in clinic_names:
                try:
                    cursor.execute("UPDATE clinics SET is_deleted = 0, deleted_at = NULL WHERE name = %s", (str(c_name),))
                except Exception:
                    pass

        conn.close()
        total = max(len(restored_doctor_ids) + len(restored_clinic_ids), len(doctor_names) + len(clinic_names))
        return jsonify({
            "success": True,
            "message": f"{total} record{'s' if total != 1 else ''} restored successfully.",
            "restored_doctor_ids": restored_doctor_ids,
            "restored_clinic_ids": restored_clinic_ids
        }), 200
    except Exception as e:
        return jsonify({"success": False, "message": str(e)}), 200

# Root test endpoint
@app.route('/')
def index():
    return jsonify({"status": "running", "service": "MedsafeLifeScience Flask API", "version": "1.0.0"}), 200

if __name__ == '__main__':
    db_status = "OK" if test_db_connection() else "FAILED / UNAVAILABLE"
    print("========================================")
    print("VayuSoftware Medsafe Backend")
    print("========================================")
    print(f"Flask Host        : 0.0.0.0")
    print(f"Flask Port        : {FLASK_PORT}")
    print(f"Database Host     : {DB_HOST}")
    print(f"Database Port     : {DB_PORT}")
    print(f"Database Status   : {db_status}")
    print(f"NGROK Target      : http://127.0.0.1:{FLASK_PORT} or WAMP Port 80")
    print(f"Health Endpoint   : http://127.0.0.1:{FLASK_PORT}/api/health")
    print("========================================")
    app.run(host='0.0.0.0', port=FLASK_PORT, debug=False)
