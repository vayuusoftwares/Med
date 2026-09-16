<?php
error_reporting(0);
ini_set('display_errors', 0);
date_default_timezone_set('Asia/Kolkata');

/**
 * get_attendance_history.php
 * Returns check-in / check-out records from attendance_history table.
 * Query params:
 *   user_id  (optional) – filter by user
 *   type     (optional) – 'check_in' | 'check_out'
 *   date     (optional) – YYYY-MM-DD
 */
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

// Auto-create table if it doesn't exist (safe guard)
$conn->query("CREATE TABLE IF NOT EXISTS attendance_history (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id       INT UNSIGNED NOT NULL,
    sales_rep_name VARCHAR(120) NOT NULL,
    type          ENUM('check_in','check_out') NOT NULL,
    lat           DOUBLE NOT NULL,
    lng           DOUBLE NOT NULL,
    address       VARCHAR(500) NULL DEFAULT '',
    notes         TEXT NULL,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
)");

$where = ["1=1"];
$params = [];
$types  = '';

// Filter by user_id
if (isset($_GET['user_id']) && intval($_GET['user_id']) > 0) {
    $where[]  = "user_id = ?";
    $types   .= 'i';
    $params[] = intval($_GET['user_id']);
}

// Filter by type: check_in / check_out
if (isset($_GET['type']) && in_array($_GET['type'], ['check_in', 'check_out'])) {
    $where[]  = "type = ?";
    $types   .= 's';
    $params[] = $_GET['type'];
}

// Filter by date: YYYY-MM-DD
if (!empty($_GET['date'])) {
    $where[]  = "DATE(created_at) = ?";
    $types   .= 's';
    $params[] = $_GET['date'];
}

$sql  = "SELECT id, user_id, sales_rep_name, type, lat, lng, address, notes, created_at
         FROM attendance_history
         WHERE " . implode(" AND ", $where) . "
         ORDER BY created_at DESC";

$stmt = $conn->prepare($sql);
if ($types) {
    $stmt->bind_param($types, ...$params);
}
$stmt->execute();
$result = $stmt->get_result();

$history = [];
while ($row = $result->fetch_assoc()) {
    $history[] = [
        "id"             => (int)$row['id'],
        "user_id"        => (int)$row['user_id'],
        "sales_rep_name" => (string)$row['sales_rep_name'],
        "type"           => (string)$row['type'],
        "lat"            => (float)$row['lat'],
        "lng"            => (float)$row['lng'],
        "address"        => (string)($row['address'] ?? ''),
        "notes"          => (string)($row['notes'] ?? ''),
        "created_at"     => (string)$row['created_at'],
    ];
}

echo json_encode([
    "success" => true,
    "count"   => count($history),
    "history" => $history,
]);

$stmt->close();
$conn->close();
?>
