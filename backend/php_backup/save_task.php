<?php
error_reporting(0);
ini_set('display_errors', 0);

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE");
header("Access-Control-Allow-Headers: *");
header('Content-Type: application/json; charset=UTF-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { exit(0); }

$conn = new mysqli("localhost", "root", "", "medsafe_db");
if ($conn->connect_error) {
    echo json_encode(["success" => false, "message" => "DB connection failed."]);
    exit;
}

$data = json_decode(file_get_contents("php://input"), true);
$user_id        = (int)($data['user_id'] ?? 0);
$sales_rep_name = trim($data['sales_rep_name'] ?? '');
$task_basis     = trim($data['task_basis'] ?? '');
$doctor_name    = trim($data['doctor_name'] ?? '');
$clinic_name    = trim($data['clinic_name'] ?? '');
$task_category  = trim($data['task_category'] ?? '');
$source_lat     = (float)($data['source_lat'] ?? 0);
$source_lng     = (float)($data['source_lng'] ?? 0);
$clinic_lat     = (float)($data['clinic_lat'] ?? 0);
$clinic_lng     = (float)($data['clinic_lng'] ?? 0);
$clinic_address = trim($data['clinic_address'] ?? '');
$notes          = trim($data['notes'] ?? '');

if ($user_id < 0 || !$task_basis || !$doctor_name || !$clinic_name) {
    echo json_encode(["success" => false, "message" => "Missing required fields."]);
    exit;
}

// Auto-create column if missing in tasks table
$conn->query("SHOW COLUMNS FROM tasks LIKE 'task_category'");
if ($conn->affected_rows == 0) {
    $conn->query("ALTER TABLE tasks ADD COLUMN task_category VARCHAR(100) AFTER clinic_name");
}
$conn->query("SHOW COLUMNS FROM tasks LIKE 'sales_rep_name'");
if ($conn->affected_rows == 0) {
    $conn->query("ALTER TABLE tasks ADD COLUMN sales_rep_name VARCHAR(100) AFTER user_id");
}
$conn->query("SHOW COLUMNS FROM tasks LIKE 'source_lat'");
if ($conn->affected_rows == 0) {
    $conn->query("ALTER TABLE tasks ADD COLUMN source_lat DOUBLE AFTER task_category");
    $conn->query("ALTER TABLE tasks ADD COLUMN source_lng DOUBLE AFTER source_lat");
}

$stmt = $conn->prepare(
    "INSERT INTO tasks (user_id, sales_rep_name, task_basis, doctor_name, clinic_name, task_category, source_lat, source_lng, clinic_lat, clinic_lng, clinic_address, notes, status)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')"
);
$stmt->bind_param("isssssddddss", $user_id, $sales_rep_name, $task_basis, $doctor_name, $clinic_name, $task_category, $source_lat, $source_lng, $clinic_lat, $clinic_lng, $clinic_address, $notes);

if ($stmt->execute()) {
    echo json_encode(["success" => true, "message" => "Task saved!", "task_id" => $conn->insert_id]);
} else {
    echo json_encode(["success" => false, "message" => "Failed to save task: " . $conn->error]);
}

$stmt->close();
$conn->close();
?>
