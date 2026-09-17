<?php
$servername = "localhost";
$username = "root";
$password = "";

$conn = new mysqli($servername, $username, $password);
if ($conn->connect_error) {
  die("Connection failed: " . $conn->connect_error);
}

$conn->query("CREATE DATABASE IF NOT EXISTS medsafe_db");
echo "Database medsafe_db created/exists.<br>";
$conn->select_db("medsafe_db");

require_once __DIR__ . '/performance_engine.php';

// ── Clean legacy unused tables ─────────────────────────────────────────────
$conn->query("DROP TABLE IF EXISTS admin_users, sales_users, fetch_loc");

// ── users ──────────────────────────────────────────────────────────────────
$conn->query("CREATE TABLE IF NOT EXISTS users (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    phone VARCHAR(20) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    role ENUM('sales_rep','admin') NOT NULL DEFAULT 'sales_rep',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
)");
echo "Table users OK.<br>";

// ── Ensure Admin User Exists ───────────────────────────────────────────────
$adminHash = password_hash('Med@2026', PASSWORD_BCRYPT);
$conn->query("INSERT INTO users (name, email, phone, password_hash, role) 
              VALUES ('Admin', 'medsafelifescience', '0000000000', '$adminHash', 'admin') 
              ON DUPLICATE KEY UPDATE password_hash='$adminHash', role='admin'");
echo "Admin user (medsafelifescience / Med@2026) ready.<br>";

// ── doctors ────────────────────────────────────────────────────────────────
$conn->query("CREATE TABLE IF NOT EXISTS doctors (
    id INT(6) UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    speciality VARCHAR(100) NOT NULL,
    phone VARCHAR(50) NOT NULL DEFAULT '',
    added_by INT UNSIGNED NOT NULL DEFAULT 0,
    is_deleted TINYINT(1) NOT NULL DEFAULT 0,
    deleted_at DATETIME NULL
)");
$doctorCols = [
    'phone' => "VARCHAR(50) NOT NULL DEFAULT ''",
    'area' => "VARCHAR(100) NOT NULL DEFAULT ''",
    'added_by' => "INT UNSIGNED NOT NULL DEFAULT 0",
    'is_deleted' => "TINYINT(1) NOT NULL DEFAULT 0",
    'deleted_at' => "DATETIME NULL"
];
foreach ($doctorCols as $col => $def) {
    $chk = $conn->query("SHOW COLUMNS FROM doctors LIKE '$col'");
    if ($chk && $chk->num_rows == 0) {
        $conn->query("ALTER TABLE doctors ADD COLUMN $col $def");
    }
}
echo "Table doctors OK.<br>";

// ── clinics ────────────────────────────────────────────────────────────────
$conn->query("CREATE TABLE IF NOT EXISTS clinics (
    id INT(6) UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    lat DOUBLE NOT NULL,
    lng DOUBLE NOT NULL,
    address VARCHAR(255) NOT NULL,
    phone VARCHAR(50) NOT NULL DEFAULT '',
    map_url TEXT NULL,
    area VARCHAR(100) NOT NULL DEFAULT '',
    added_by INT UNSIGNED NOT NULL DEFAULT 0,
    is_deleted TINYINT(1) NOT NULL DEFAULT 0,
    deleted_at DATETIME NULL
)");
$clinicCols = [
    'phone' => "VARCHAR(50) NOT NULL DEFAULT ''",
    'map_url' => "TEXT NULL",
    'area' => "VARCHAR(100) NOT NULL DEFAULT ''",
    'added_by' => "INT UNSIGNED NOT NULL DEFAULT 0",
    'is_deleted' => "TINYINT(1) NOT NULL DEFAULT 0",
    'deleted_at' => "DATETIME NULL"
];
foreach ($clinicCols as $col => $def) {
    $chk = $conn->query("SHOW COLUMNS FROM clinics LIKE '$col'");
    if ($chk && $chk->num_rows == 0) {
        $conn->query("ALTER TABLE clinics ADD COLUMN $col $def");
    }
}
echo "Table clinics OK.<br>";

// ── areas ──────────────────────────────────────────────────────────────────
$conn->query("CREATE TABLE IF NOT EXISTS areas (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    added_by INT UNSIGNED NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
)");
echo "Table areas OK.<br>";

// ── deleted_areas ──────────────────────────────────────────────────────────
$conn->query("CREATE TABLE IF NOT EXISTS deleted_areas (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    area VARCHAR(100) NOT NULL UNIQUE,
    deleted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
)");
echo "Table deleted_areas OK.<br>";

// ── tasks ──────────────────────────────────────────────────────────────────
$conn->query("CREATE TABLE IF NOT EXISTS tasks (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id INT UNSIGNED NOT NULL,
    sales_rep_name VARCHAR(100),
    task_basis VARCHAR(20) NOT NULL,
    doctor_name VARCHAR(100) NOT NULL,
    clinic_name VARCHAR(100) NOT NULL,
    task_category VARCHAR(100),
    area VARCHAR(100) NOT NULL DEFAULT '',
    source_lat DOUBLE,
    source_lng DOUBLE,
    clinic_lat DOUBLE NOT NULL,
    clinic_lng DOUBLE NOT NULL,
    clinic_address VARCHAR(255) NOT NULL,
    notes TEXT,
    status ENUM('pending','completed') NOT NULL DEFAULT 'pending',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
)");

// Ensure newly added columns exist if table was previously created
$extraCols = [
    'sales_rep_name'             => "VARCHAR(100) NOT NULL DEFAULT '' AFTER user_id",
    'created_by_id'              => "INT UNSIGNED NOT NULL DEFAULT 0",
    'created_by_name'            => "VARCHAR(100) NOT NULL DEFAULT 'Admin'",
    'created_by_role'            => "ENUM('admin','sales_rep') NOT NULL DEFAULT 'admin'",
    'assigned_to_id'             => "INT UNSIGNED NOT NULL DEFAULT 0",
    'assigned_to_name'           => "VARCHAR(100) NOT NULL DEFAULT ''",
    'task_name'                  => "VARCHAR(150) NOT NULL DEFAULT 'Customer Visit'",
    'task_category'              => "VARCHAR(100) AFTER clinic_name",
    'area'                       => "VARCHAR(100) NOT NULL DEFAULT ''",
    'source_lat'                 => "DOUBLE AFTER task_category",
    'source_lng'                 => "DOUBLE AFTER source_lat",
    'source_address'             => "VARCHAR(255) NULL DEFAULT ''",
    'assigned_at'                => "DATETIME NULL DEFAULT CURRENT_TIMESTAMP",
    'start_date_time'            => "DATETIME NULL",
    'end_date_time'              => "DATETIME NULL",
    'started_at'                 => "DATETIME NULL",
    'deadline_date_time'         => "DATETIME NULL",
    'destination_reached_at'     => "DATETIME NULL",
    'target_duration_seconds'    => "INT NULL DEFAULT 300",
    'target_deadline_at'         => "DATETIME NULL",
    'destination_reached_lat'    => "DOUBLE NULL",
    'destination_reached_lng'    => "DOUBLE NULL",
    'destination_reached_distance_meters' => "DOUBLE NULL",
    'time_inside_destination_seconds'     => "INT NULL DEFAULT 0",
    'is_inside_destination'               => "TINYINT(1) NOT NULL DEFAULT 0",
    'last_destination_distance_meters'    => "DOUBLE NULL",
    'overtime_started_at'        => "DATETIME NULL",
    'overtime_duration_seconds'  => "INT NULL DEFAULT 0",
    'overtime_reason'            => "TEXT NULL",
    'completion_result'          => "VARCHAR(50) NULL DEFAULT ''",
    'final_distance_meters'      => "DOUBLE NULL",
    'final_lat'                  => "DOUBLE NULL",
    'final_lng'                  => "DOUBLE NULL",
    'checked_out_at'             => "DATETIME NULL",
    'checkout_date'              => "DATE NULL",
    'checkout_time'              => "TIME NULL",
    'checkout_lat'               => "DOUBLE NULL",
    'checkout_lng'               => "DOUBLE NULL",
    'destination_distance_meters'=> "DOUBLE NULL",
    'stable_duration_seconds'    => "INT NULL DEFAULT 60",
    'checkout_type'              => "VARCHAR(50) NULL DEFAULT 'manual'",
    'last_latitude'              => "DOUBLE NULL",
    'last_longitude'             => "DOUBLE NULL",
    'last_location_update'       => "DATETIME NULL",
    'no_movement_started_at'     => "DATETIME NULL",
    'updated_at'                 => "DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP"
];

foreach ($extraCols as $col => $def) {
    $r = $conn->query("SHOW COLUMNS FROM tasks LIKE '$col'");
    if ($r && $r->num_rows == 0) {
        $conn->query("ALTER TABLE tasks ADD COLUMN $col $def");
    }
}
$conn->query("ALTER TABLE tasks MODIFY COLUMN status VARCHAR(50) NOT NULL DEFAULT 'pending'");
echo "Table tasks OK.<br>";

// ── Initialize Performance Schema ──────────────────────────────────────────
ensure_performance_schema($conn);
echo "Table sales_rep_performance OK.<br>";

// Synchronize all existing real database tasks into performance table
sync_all_existing_tasks_performance($conn);
echo "Real tasks performance synced.<br>";

// ── order_pdfs ─────────────────────────────────────────────────────────────
$conn->query("CREATE TABLE IF NOT EXISTS order_pdfs (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id INT UNSIGNED NOT NULL,
    doctor_name VARCHAR(100) NOT NULL,
    products_json TEXT NOT NULL,
    pdf_filename VARCHAR(255) NOT NULL,
    saved_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
)");
echo "Table order_pdfs OK.<br>";

// ── Seed dummy doctors ──────────────────────────────────────────────────────
$r = $conn->query("SELECT id FROM doctors");
if ($r->num_rows == 0) {
    $conn->query("INSERT INTO doctors (name, speciality) VALUES ('Dr. Ramesh Kumar', 'General Physician')");
    $conn->query("INSERT INTO doctors (name, speciality) VALUES ('Dr. Priya Nair', 'Cardiologist')");
    $conn->query("INSERT INTO doctors (name, speciality) VALUES ('Dr. Sanjay Gupta', 'Neurologist')");
    $conn->query("INSERT INTO doctors (name, speciality) VALUES ('Dr. Anitha Rao', 'Dermatologist')");
    $conn->query("INSERT INTO doctors (name, speciality) VALUES ('Dr. Vikram Sharma', 'Orthopedic')");
    echo "Dummy doctors inserted.<br>";
}

// ── Seed dummy clinics ──────────────────────────────────────────────────────
$r = $conn->query("SELECT id FROM clinics");
if ($r->num_rows == 0) {
    $conn->query("INSERT INTO clinics (name, lat, lng, address) VALUES ('Apollo Health Clinic', 13.0827, 80.2707, '21 MG Road, Chennai')");
    $conn->query("INSERT INTO clinics (name, lat, lng, address) VALUES ('City Care Centre', 13.0674, 80.2376, '45 Anna Salai, Chennai')");
    $conn->query("INSERT INTO clinics (name, lat, lng, address) VALUES ('Fortis Hospital', 13.0116, 80.2366, 'Arco Road, Chennai')");
    $conn->query("INSERT INTO clinics (name, lat, lng, address) VALUES ('MIOT International', 13.0358, 80.1938, 'Mount Poonamallee Road, Chennai')");
    $conn->query("INSERT INTO clinics (name, lat, lng, address) VALUES ('Kauvery Hospital', 13.0519, 80.2428, 'Radha Nagar, Chennai')");
    echo "Dummy clinics inserted.<br>";
}

// ── attendance_history (Daily Sales Rep Check-in / Check-out ONLY) ──
$conn->query("CREATE TABLE IF NOT EXISTS attendance_history (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id INT UNSIGNED NOT NULL,
    sales_rep_name VARCHAR(100) NOT NULL,
    type VARCHAR(50) NOT NULL DEFAULT 'check_in',
    lat DOUBLE NOT NULL,
    lng DOUBLE NOT NULL,
    address VARCHAR(255) NULL,
    notes TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_created_at (created_at)
)");
echo "Table attendance_history OK.<br>";

// ── clinic_location_tracking (1-min live location tracking for each clinic visit) ──
$conn->query("CREATE TABLE IF NOT EXISTS clinic_location_tracking (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    task_id INT UNSIGNED NOT NULL,
    user_id INT UNSIGNED NOT NULL,
    sales_rep_name VARCHAR(100) NOT NULL,
    doctor_name VARCHAR(255) NULL DEFAULT '',
    clinic_name VARCHAR(255) NULL DEFAULT '',
    clinic_address TEXT NULL,
    type VARCHAR(50) NOT NULL DEFAULT 'task_tracking',
    lat DECIMAL(10, 8) NOT NULL,
    lng DECIMAL(11, 8) NOT NULL,
    notes TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_task_id (task_id),
    INDEX idx_user_id (user_id),
    INDEX idx_created_at (created_at)
)");
echo "Table clinic_location_tracking OK.<br>";

$conn->close();
echo "<br><strong>Setup complete! All tables created.</strong>";
?>
