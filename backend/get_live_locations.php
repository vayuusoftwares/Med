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
    echo json_encode(["success" => false, "message" => "DB connection failed."]);
    exit;
}

// Fetch users with role = 'sales_rep' and their latest attendance ping
$sql = "SELECT u.id as user_id, u.name as sales_rep_name, ah.type, ah.lat, ah.lng, ah.created_at as recorded_at
        FROM users u
        INNER JOIN (
            SELECT user_id, MAX(id) as max_id
            FROM attendance_history
            GROUP BY user_id
        ) latest ON u.id = latest.user_id
        INNER JOIN attendance_history ah ON latest.max_id = ah.id
        WHERE u.role = 'sales_rep'";

$result = $conn->query($sql);

$reps = [];
if ($result && $result->num_rows > 0) {
    while ($row = $result->fetch_assoc()) {
        $reps[] = [
            "user_id"        => (int)$row['user_id'],
            "sales_rep_name" => $row['sales_rep_name'],
            "type"           => $row['type'] ?? 'check_in',
            "lat"            => (float)$row['lat'],
            "lng"            => (float)$row['lng'],
            "accuracy"       => 10.0,
            "recorded_at"    => date('c', strtotime($row['recorded_at'])),
        ];
    }
}

echo json_encode([
    "success" => true,
    "reps"    => $reps
]);

$conn->close();
?>
