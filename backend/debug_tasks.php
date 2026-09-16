<?php
// Quick debug endpoint — shows what's in the tasks table
header("Access-Control-Allow-Origin: *");
header('Content-Type: application/json');

$conn = new mysqli("localhost", "root", "", "medsafe_db");
if ($conn->connect_error) {
    echo json_encode(["error" => $conn->connect_error]);
    exit;
}

// Show all users
$users = [];
$r = $conn->query("SELECT id, name, email, role FROM users ORDER BY id");
while ($row = $r->fetch_assoc()) $users[] = $row;

// Show all tasks
$tasks = [];
$r2 = $conn->query("SELECT id, user_id, sales_rep_name, status, doctor_name, clinic_name FROM tasks ORDER BY id");
while ($row = $r2->fetch_assoc()) $tasks[] = $row;

echo json_encode([
    "users" => $users,
    "tasks" => $tasks,
    "tasks_count" => count($tasks),
]);
$conn->close();
?>
