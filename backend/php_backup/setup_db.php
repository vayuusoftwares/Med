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
    speciality VARCHAR(100) NOT NULL
)");
echo "Table doctors OK.<br>";

// ── clinics ────────────────────────────────────────────────────────────────
$conn->query("CREATE TABLE IF NOT EXISTS clinics (
    id INT(6) UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    lat DOUBLE NOT NULL,
    lng DOUBLE NOT NULL,
    address VARCHAR(255) NOT NULL
)");
echo "Table clinics OK.<br>";

// ── tasks ──────────────────────────────────────────────────────────────────
$conn->query("CREATE TABLE IF NOT EXISTS tasks (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id INT UNSIGNED NOT NULL,
    sales_rep_name VARCHAR(100),
    task_basis VARCHAR(20) NOT NULL,
    doctor_name VARCHAR(100) NOT NULL,
    clinic_name VARCHAR(100) NOT NULL,
    task_category VARCHAR(100),
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
    'source_lat'                 => "DOUBLE AFTER task_category",
    'source_lng'                 => "DOUBLE AFTER source_lat",
    'source_address'             => "VARCHAR(255) NULL DEFAULT ''",
    'assigned_at'                => "DATETIME NULL DEFAULT CURRENT_TIMESTAMP",
    'started_at'                 => "DATETIME NULL",
    'destination_reached_at'     => "DATETIME NULL",
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
echo "Table tasks OK.<br>";

// ── Seed dummy tasks ────────────────────────────────────────────────────────
$rTasks = $conn->query("SELECT id FROM tasks");
if ($rTasks->num_rows == 0) {
    $conn->query("INSERT INTO tasks (user_id, sales_rep_name, task_basis, doctor_name, clinic_name, task_category, source_lat, source_lng, clinic_lat, clinic_lng, clinic_address, notes, status) 
                  VALUES (1, 'Abikrishna', 'Daily', 'Dr. Ramesh Kumar', 'Apollo Health Clinic', 'Samples', 13.0827, 80.2707, 13.0827, 80.2707, '21 MG Road, Chennai', 'Deliver sample products and discuss new medical products catalog.', 'pending')");
    $conn->query("INSERT INTO tasks (user_id, sales_rep_name, task_basis, doctor_name, clinic_name, task_category, source_lat, source_lng, clinic_lat, clinic_lng, clinic_address, notes, status) 
                  VALUES (1, 'Abikrishna', 'Daily', 'Dr. Priya Nair', 'City Care Centre', 'Gifts', 13.0674, 80.2376, 13.0674, 80.2376, '45 Anna Salai, Chennai', 'Provide gift box and latest LBL card.', 'pending')");
    $conn->query("INSERT INTO tasks (user_id, sales_rep_name, task_basis, doctor_name, clinic_name, task_category, source_lat, source_lng, clinic_lat, clinic_lng, clinic_address, notes, status) 
                  VALUES (1, 'Abikrishna', 'Weekly', 'Dr. Sanjay Gupta', 'Fortis Hospital', 'About product', 13.0116, 80.2366, 13.0116, 80.2366, 'Arco Road, Chennai', 'Product presentation completed successfully.', 'completed')");
    echo "Dummy tasks inserted.<br>";
}

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

// ── attendance_history ───────────────────────────────────────────────────
$conn->query("CREATE TABLE IF NOT EXISTS attendance_history (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id INT UNSIGNED NOT NULL,
    sales_rep_name VARCHAR(100) NOT NULL,
    type ENUM('check_in', 'check_out') NOT NULL,
    lat DOUBLE NOT NULL,
    lng DOUBLE NOT NULL,
    address VARCHAR(255) NULL,
    notes TEXT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
)");
echo "Table attendance_history OK.<br>";

// ── Seed dummy attendance history ─────────────────────────────────────────
$r = $conn->query("SELECT id FROM attendance_history");
if ($r->num_rows == 0) {
    // Check if sales reps exist to associate user_id
    $uRes = $conn->query("SELECT id, name FROM users WHERE role='sales_rep' LIMIT 3");
    $salesReps = [];
    while ($row = $uRes->fetch_assoc()) {
        $salesReps[] = $row;
    }
    if (empty($salesReps)) {
        $salesReps = [
            ['id' => 1, 'name' => 'Rajesh Sharma'],
            ['id' => 2, 'name' => 'Priya Patel'],
            ['id' => 3, 'name' => 'Karthik Subramanian']
        ];
    }
    
    $samplePings = [
        ['type' => 'check_in',  'lat' => 13.0827, 'lng' => 80.2707, 'address' => 'Central Hub, MG Road, Chennai', 'notes' => 'Morning check-in at office'],
        ['type' => 'check_out', 'lat' => 13.0674, 'lng' => 80.2376, 'address' => 'City Care Centre, Anna Salai', 'notes' => 'Completed clinic visit check-out'],
        ['type' => 'check_in',  'lat' => 13.0116, 'lng' => 80.2366, 'address' => 'Fortis Hospital, Chennai', 'notes' => 'Afternoon clinic visit check-in'],
        ['type' => 'check_out', 'lat' => 13.0358, 'lng' => 80.1938, 'address' => 'MIOT Hospital, Poonamallee', 'notes' => 'Evening duty check-out'],
    ];

    foreach ($salesReps as $rep) {
        $repId = (int)$rep['id'];
        $repName = $conn->real_escape_string($rep['name']);
        foreach ($samplePings as $idx => $p) {
            $t = $p['type'];
            $lat = $p['lat'] + (rand(-10, 10) * 0.005);
            $lng = $p['lng'] + (rand(-10, 10) * 0.005);
            $addr = $conn->real_escape_string($p['address']);
            $note = $conn->real_escape_string($p['notes']);
            $timeOffset = (4 - $idx) * 2;
            $conn->query("INSERT INTO attendance_history (user_id, sales_rep_name, type, lat, lng, address, notes, created_at) 
                          VALUES ($repId, '$repName', '$t', $lat, $lng, '$addr', '$note', DATE_SUB(NOW(), INTERVAL $timeOffset HOUR))");
        }
    }
    echo "Dummy attendance history inserted.<br>";
}

$conn->close();
echo "<br><strong>Setup complete! All tables created.</strong>";
?>
