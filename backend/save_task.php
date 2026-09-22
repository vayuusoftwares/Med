<?php
error_reporting(0);
ini_set('display_errors', 0);
date_default_timezone_set('Asia/Kolkata');

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE");
header("Access-Control-Allow-Headers: *");
header('Content-Type: application/json; charset=UTF-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { exit(0); }

require_once __DIR__ . '/performance_engine.php';

$conn = new mysqli("localhost", "root", "", "medsafe_db");
if ($conn->connect_error) {
    echo json_encode(["success" => false, "message" => "DB connection failed."]);
    exit;
}

ensure_performance_schema($conn);

$data = json_decode(file_get_contents("php://input"), true);
$user_id            = (int)($data['user_id'] ?? 0);
$sales_rep_name     = trim($data['sales_rep_name'] ?? '');
$task_basis         = trim($data['task_basis'] ?? '');
$doctor_name        = trim($data['doctor_name'] ?? '');
$clinic_name        = trim($data['clinic_name'] ?? '');
$task_category      = trim($data['task_category'] ?? '');
$source_lat         = (float)($data['source_lat'] ?? 0);
$source_lng         = (float)($data['source_lng'] ?? 0);
$clinic_lat         = (float)($data['clinic_lat'] ?? 0);
$clinic_lng         = (float)($data['clinic_lng'] ?? 0);
$clinic_address     = trim($data['clinic_address'] ?? '');
$area               = trim($data['area'] ?? '');
$notes              = trim($data['notes'] ?? '');
$deadline_raw       = trim($data['deadline_date_time'] ?? ($data['deadline'] ?? ''));

$deadline_formatted = null;
if (!empty($deadline_raw)) {
    $parsedDl = parse_kolkata_datetime($deadline_raw);
    if ($parsedDl) {
        $deadline_formatted = $parsedDl->format('Y-m-d H:i:s');
    }
}

if ($user_id < 0 || !$task_basis || !$doctor_name || !$clinic_name) {
    echo json_encode(["success" => false, "message" => "Missing required fields."]);
    exit;
}

$r = $conn->query("SHOW COLUMNS FROM `tasks` LIKE 'area'");
if ($r && $r->num_rows == 0) {
    $conn->query("ALTER TABLE `tasks` ADD COLUMN `area` VARCHAR(100) NOT NULL DEFAULT ''");
}

$task_id = (int)($data['task_id'] ?? ($data['id'] ?? 0));

if ($task_id > 0) {
    $stmt = $conn->prepare(
        "UPDATE tasks SET user_id = ?, sales_rep_name = ?, task_basis = ?, doctor_name = ?, clinic_name = ?, task_category = ?, area = ?, source_lat = ?, source_lng = ?, clinic_lat = ?, clinic_lng = ?, clinic_address = ?, notes = ?, deadline_date_time = COALESCE(?, deadline_date_time) WHERE id = ?"
    );
    $stmt->bind_param("issssssddddsssi", $user_id, $sales_rep_name, $task_basis, $doctor_name, $clinic_name, $task_category, $area, $source_lat, $source_lng, $clinic_lat, $clinic_lng, $clinic_address, $notes, $deadline_formatted, $task_id);
    if ($stmt->execute()) {
        // Fetch updated task and sync performance
        $fetchRes = $conn->query("SELECT * FROM tasks WHERE id = $task_id");
        if ($fetchRes && $taskRow = $fetchRes->fetch_assoc()) {
            sync_task_performance_record($conn, $taskRow);
        }
        echo json_encode(["success" => true, "message" => "Task updated!", "task_id" => $task_id]);
    } else {
        echo json_encode(["success" => false, "message" => "Failed to update task: " . $conn->error]);
    }
    $stmt->close();
} else {
    $stmt = $conn->prepare(
        "INSERT INTO tasks (user_id, sales_rep_name, task_basis, doctor_name, clinic_name, task_category, area, source_lat, source_lng, clinic_lat, clinic_lng, clinic_address, notes, deadline_date_time, status)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')"
    );
    $stmt->bind_param("issssssddddsss", $user_id, $sales_rep_name, $task_basis, $doctor_name, $clinic_name, $task_category, $area, $source_lat, $source_lng, $clinic_lat, $clinic_lng, $clinic_address, $notes, $deadline_formatted);

    if ($stmt->execute()) {
        $newId = $conn->insert_id;
        // Fetch newly created task and sync performance
        $fetchRes = $conn->query("SELECT * FROM tasks WHERE id = $newId");
        if ($fetchRes && $taskRow = $fetchRes->fetch_assoc()) {
            sync_task_performance_record($conn, $taskRow);
        }
        echo json_encode(["success" => true, "message" => "Task saved!", "task_id" => $newId]);
    } else {
        echo json_encode(["success" => false, "message" => "Failed to save task: " . $conn->error]);
    }
    $stmt->close();
}

$conn->close();
?>
