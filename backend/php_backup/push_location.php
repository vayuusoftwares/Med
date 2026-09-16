<?php
error_reporting(0);
ini_set('display_errors', 0);
date_default_timezone_set('Asia/Kolkata');

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE");
header("Access-Control-Allow-Headers: *");
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { exit(0); }

$conn = new mysqli("localhost", "root", "", "medsafe_db");
if ($conn->connect_error) {
    echo json_encode(["success" => false, "message" => "DB connection failed."]);
    exit;
}

$raw  = file_get_contents("php://input");
$data = json_decode($raw, true);

if (!$data) {
    echo json_encode(["success" => false, "message" => "Invalid JSON payload"]);
    exit;
}

$userId        = isset($data['user_id'])        ? intval($data['user_id'])         : 0;
$salesRepName  = isset($data['sales_rep_name']) ? trim($data['sales_rep_name'])    : 'Sales Rep';
$lat           = isset($data['lat'])            ? floatval($data['lat'])           : null;
$lng           = isset($data['lng'])            ? floatval($data['lng'])           : null;

if ($userId <= 0 || $lat === null || $lng === null || ($lat == 0 && $lng == 0)) {
    echo json_encode(["success" => false, "message" => "Invalid location payload."]);
    exit;
}

// Check if latest attendance record is check_out -> do not overwrite check_out with check_in ping
$checkStmt = $conn->prepare("SELECT type FROM attendance_history WHERE user_id = ? ORDER BY id DESC LIMIT 1");
$checkStmt->bind_param("i", $userId);
$checkStmt->execute();
$checkRes = $checkStmt->get_result();
if ($checkRes && $checkRes->num_rows > 0) {
    $lastRec = $checkRes->fetch_assoc();
    if (strtolower(trim($lastRec['type'] ?? '')) === 'check_out') {
        // User is checked out; ignore background location pushes
        $checkStmt->close();
        $conn->close();
        echo json_encode(["success" => true, "message" => "User currently checked out, ping ignored."]);
        exit;
    }
}
$checkStmt->close();

$stmt = $conn->prepare(
    "INSERT INTO attendance_history (user_id, sales_rep_name, type, lat, lng, address, notes)
     VALUES (?, ?, 'check_in', ?, ?, 'Live Ping', 'Automated location push')"
);
$stmt->bind_param("isdd", $userId, $salesRepName, $lat, $lng);

if ($stmt->execute()) {
    echo json_encode(["success" => true, "message" => "Location updated."]);
} else {
    echo json_encode(["success" => false, "message" => "DB error: " . $stmt->error]);
}

$stmt->close();
$conn->close();
?>
