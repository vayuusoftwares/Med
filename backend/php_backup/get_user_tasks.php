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
    echo json_encode(["success" => false, "message" => "DB connection failed: " . $conn->connect_error]);
    exit;
}

$user_id        = isset($_GET['user_id']) ? intval($_GET['user_id']) : 0;
$sales_rep_name = isset($_GET['sales_rep_name']) ? trim($_GET['sales_rep_name']) : '';
$fetchAll       = (isset($_GET['all']) && $_GET['all'] == '1');

// Filter logic: if 'all=1' passed, return all tasks; otherwise filter strictly by user_id / sales_rep_name
if ($fetchAll) {
    $sql    = "SELECT * FROM tasks ORDER BY created_at DESC";
    $result = $conn->query($sql);
} else {
    $conditions = [];
    $types      = '';
    $params     = [];

    if ($user_id > 0) {
        $conditions[] = 'user_id = ?';
        $types .= 'i';
        $params[] = $user_id;
    }
    if ($sales_rep_name !== '') {
        $conditions[] = 'sales_rep_name LIKE ?';
        $types .= 's';
        $params[] = '%' . $sales_rep_name . '%';
    }

    if (!empty($conditions)) {
        $where = implode(' OR ', $conditions);
        $stmt  = $conn->prepare("SELECT * FROM tasks WHERE $where ORDER BY created_at DESC");
        if ($types) {
            $stmt->bind_param($types, ...$params);
        }
        $stmt->execute();
        $result = $stmt->get_result();
    } else {
        $result = $conn->query("SELECT * FROM tasks WHERE 1=0");
    }
}

$tasks = [];
while ($row = $result->fetch_assoc()) {
    $tasks[] = [
        "id"                          => (int)$row['id'],
        "user_id"                     => (int)($row['user_id'] ?? 0),
        "sales_rep_name"              => (string)($row['sales_rep_name'] ?? ''),
        "task_basis"                  => (string)($row['task_basis'] ?? ''),
        "doctor_name"                 => (string)($row['doctor_name'] ?? ''),
        "clinic_name"                 => (string)($row['clinic_name'] ?? ''),
        "task_category"               => (string)($row['task_category'] ?? ''),
        "source_lat"                  => isset($row['source_lat']) ? (float)$row['source_lat'] : null,
        "source_lng"                  => isset($row['source_lng']) ? (float)$row['source_lng'] : null,
        "source_address"              => (string)($row['source_address'] ?? ''),
        "clinic_lat"                  => (float)($row['clinic_lat'] ?? 0),
        "clinic_lng"                  => (float)($row['clinic_lng'] ?? 0),
        "clinic_address"              => (string)($row['clinic_address'] ?? ''),
        "notes"                       => (string)($row['notes'] ?? ''),
        "status"                      => (string)($row['status'] ?? 'pending'),
        "checkout_type"               => (string)($row['checkout_type'] ?? ''),
        "checkout_date"               => (string)($row['checkout_date'] ?? ''),
        "checkout_time"               => (string)($row['checkout_time'] ?? ''),
        "checked_out_at"              => (string)($row['checked_out_at'] ?? ''),
        "checkout_lat"                => isset($row['checkout_lat']) ? (float)$row['checkout_lat'] : null,
        "checkout_lng"                => isset($row['checkout_lng']) ? (float)$row['checkout_lng'] : null,
        "destination_distance_meters" => isset($row['destination_distance_meters']) ? (float)$row['destination_distance_meters'] : null,
        "created_at"                  => (string)($row['created_at'] ?? ''),
        "updated_at"                  => (string)($row['updated_at'] ?? ''),
    ];
}

echo json_encode([
    "success"  => true,
    "count"    => count($tasks),
    "user_id"  => $user_id,
    "rep_name" => $sales_rep_name,
    "tasks"    => $tasks,
]);

$conn->close();
?>
