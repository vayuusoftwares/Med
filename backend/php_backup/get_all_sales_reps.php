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

$sql = "SELECT id, name, email, phone, role, created_at FROM users WHERE role = 'sales_rep' ORDER BY id ASC";
$result = $conn->query($sql);

$reps = [];

if ($result && $result->num_rows > 0) {
    while ($row = $result->fetch_assoc()) {
        $userId = (int)$row['id'];
        $repName = trim($row['name']);
        
        // Fetch last attendance record matching sales_rep_name or user_id
        $attStmt = $conn->prepare("SELECT type, lat, lng, created_at FROM attendance_history WHERE LOWER(sales_rep_name) = LOWER(?) OR user_id = ? ORDER BY id DESC LIMIT 1");
        $attStmt->bind_param("si", $repName, $userId);
        $attStmt->execute();
        $attRes = $attStmt->get_result();
        
        $lastLat = null;
        $lastLng = null;
        $lastAccuracy = 10.0;
        $lastPingAt = null;
        $isOnline = false;

        if ($attRes && $attRes->num_rows > 0) {
            $att = $attRes->fetch_assoc();
            $lastLat = (float)$att['lat'];
            $lastLng = (float)$att['lng'];
            $lastPingAt = date('c', strtotime($att['created_at']));
            
            // Check in means online, Check out means offline
            $type = isset($att['type']) ? strtolower(trim($att['type'])) : '';
            $isOnline = ($type === 'check_in');
        }
        $attStmt->close();

        $reps[] = [
            "id"            => $userId,
            "name"          => $row['name'],
            "email"         => $row['email'],
            "phone"         => $row['phone'],
            "is_active"     => true,
            "created_at"    => date('c', strtotime($row['created_at'])),
            "last_lat"      => $lastLat,
            "last_lng"      => $lastLng,
            "last_accuracy" => $lastAccuracy,
            "last_ping_at"  => $lastPingAt,
            "is_online"     => $isOnline,
        ];
    }
}

echo json_encode([
    "success" => true,
    "count"   => count($reps),
    "reps"    => $reps
]);

$conn->close();
?>
