<?php
error_reporting(0);
ini_set('display_errors', 0);
date_default_timezone_set('Asia/Kolkata');

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE");
header("Access-Control-Allow-Headers: *");
header('Content-Type: application/json; charset=UTF-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { exit(0); }

$conn = new mysqli("localhost", "root", "", "medsafe_db");
if ($conn->connect_error) {
    echo json_encode(["success" => false, "message" => "DB connection failed: " . $conn->connect_error]);
    exit;
}

$rawInput = file_get_contents("php://input");
$data = json_decode($rawInput, true);
if (!is_array($data)) {
    $data = $_POST;
}

$task_id = intval($data['task_id'] ?? $data['id'] ?? $_GET['task_id'] ?? $_GET['id'] ?? 0);
$user_id = intval($data['user_id'] ?? $_GET['user_id'] ?? 0);

if ($task_id <= 0) {
    echo json_encode(["success" => false, "message" => "Invalid or missing Task ID."]);
    exit;
}

// 1. Check if task exists
$stmt = $conn->prepare("SELECT id, sales_rep_name, doctor_name, clinic_name FROM tasks WHERE id = ?");
$stmt->bind_param("i", $task_id);
$stmt->execute();
$res = $stmt->get_result();
$task = $res->fetch_assoc();
$stmt->close();

if (!$task) {
    echo json_encode(["success" => false, "message" => "Task not found in database."]);
    exit;
}

// 2. Remove associated performance record if table exists
$conn->query("DELETE FROM sales_rep_performance WHERE task_id = $task_id");

// 3. Delete task from tasks table
$delStmt = $conn->prepare("DELETE FROM tasks WHERE id = ?");
$delStmt->bind_param("i", $task_id);
$deleted = $delStmt->execute();
$delStmt->close();

if ($deleted) {
    echo json_encode([
        "success" => true,
        "message" => "Task deleted successfully.",
        "task_id" => $task_id,
        "doctor_name" => $task['doctor_name'],
        "clinic_name" => $task['clinic_name']
    ]);
} else {
    echo json_encode(["success" => false, "message" => "Failed to delete task: " . $conn->error]);
}
