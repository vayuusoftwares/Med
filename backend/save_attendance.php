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
    echo json_encode(["success" => false, "message" => "DB connection failed: " . $conn->connect_error]);
    exit;
}

// Auto-create table if it doesn't exist
$conn->query("CREATE TABLE IF NOT EXISTS attendance_history (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id       INT UNSIGNED NOT NULL,
    sales_rep_name VARCHAR(120) NOT NULL,
    type          ENUM('check_in','check_out') NOT NULL,
    lat           DOUBLE NOT NULL,
    lng           DOUBLE NOT NULL,
    address       VARCHAR(500) NULL DEFAULT '',
    notes         TEXT NULL,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user (user_id),
    INDEX idx_name (sales_rep_name),
    INDEX idx_type (type),
    INDEX idx_date (created_at)
)");

$raw  = file_get_contents("php://input");
$data = json_decode($raw, true);

if (!$data) {
    echo json_encode(["success" => false, "message" => "Invalid JSON payload"]);
    exit;
}

$userId        = isset($data['user_id'])        ? intval($data['user_id'])         : 0;
$salesRepName  = isset($data['sales_rep_name']) ? trim($data['sales_rep_name'])    : '';
$type          = isset($data['type'])           ? strtolower(trim($data['type']))  : '';
$lat           = isset($data['lat'])            ? floatval($data['lat'])           : 0.0;
$lng           = isset($data['lng'])            ? floatval($data['lng'])           : 0.0;
$address       = isset($data['address'])        ? trim($data['address'])           : '';
$notes         = isset($data['notes'])          ? trim($data['notes'])             : '';

// Validation
if ($userId <= 0 && empty($salesRepName)) {
    echo json_encode(["success" => false, "message" => "User identifier required"]);
    exit;
}
if (!in_array($type, ['check_in', 'check_out'])) {
    echo json_encode(["success" => false, "message" => "type must be check_in or check_out, got: $type"]);
    exit;
}

// If lat/lng missing, try to fill from previous record for this user
if ($lat == 0.0 && $lng == 0.0) {
    $prevStmt = $conn->prepare("SELECT lat, lng, address FROM attendance_history WHERE LOWER(sales_rep_name) = LOWER(?) OR user_id = ? ORDER BY id DESC LIMIT 1");
    $prevStmt->bind_param("si", $salesRepName, $userId);
    $prevStmt->execute();
    $prevRes = $prevStmt->get_result();
    if ($prevRes && $prevRes->num_rows > 0) {
        $p = $prevRes->fetch_assoc();
        $lat = floatval($p['lat']);
        $lng = floatval($p['lng']);
        if (empty($address)) {
            $address = $p['address'];
        }
    }
    $prevStmt->close();
}

$stmt = $conn->prepare(
    "INSERT INTO attendance_history (user_id, sales_rep_name, type, lat, lng, address, notes)
     VALUES (?, ?, ?, ?, ?, ?, ?)"
);
$stmt->bind_param("issddss", $userId, $salesRepName, $type, $lat, $lng, $address, $notes);

if ($stmt->execute()) {
    echo json_encode([
        "success"   => true,
        "message"   => "Attendance saved successfully",
        "record_id" => $stmt->insert_id,
        "type"      => $type,
        "lat"       => $lat,
        "lng"       => $lng,
        "saved_at"  => date('Y-m-d H:i:s'),
    ]);
} else {
    echo json_encode(["success" => false, "message" => "DB error: " . $stmt->error]);
}

$stmt->close();
$conn->close();
?>
