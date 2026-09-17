<?php
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE");
header("Access-Control-Allow-Headers: *");
header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { exit(0); }

$conn = new mysqli("localhost", "root", "", "medsafe_db");
if ($conn->connect_error) {
    echo json_encode(["success" => false, "message" => "DB connection failed."]);
    exit;
}

$user_id = (int)($_GET['user_id'] ?? 0);
if (!$user_id) {
    echo json_encode(["success" => false, "message" => "user_id is required."]);
    exit;
}

$stmt = $conn->prepare(
    "SELECT id, sales_rep_name, task_basis, doctor_name, clinic_name, task_category, area, clinic_lat, clinic_lng, clinic_address, notes, status, created_at
     FROM tasks WHERE user_id = ? AND status = 'pending' ORDER BY created_at DESC"
);
$stmt->bind_param("i", $user_id);
$stmt->execute();
$result = $stmt->get_result();

$tasks = [];
while ($row = $result->fetch_assoc()) {
    $tasks[] = [
        "id"             => (int)$row['id'],
        "sales_rep_name" => $row['sales_rep_name'] ?? '',
        "task_basis"     => $row['task_basis'],
        "doctor_name"    => $row['doctor_name'],
        "clinic_name"    => $row['clinic_name'],
        "task_category"  => $row['task_category'] ?? '',
        "area"           => $row['area'] ?? '',
        "clinic_lat"     => (float)$row['clinic_lat'],
        "clinic_lng"     => (float)$row['clinic_lng'],
        "clinic_address" => $row['clinic_address'],
        "notes"          => $row['notes'],
        "status"         => $row['status'],
        "created_at"     => $row['created_at'],
    ];
}

echo json_encode(["success" => true, "tasks" => $tasks]);

$stmt->close();
$conn->close();
?>
