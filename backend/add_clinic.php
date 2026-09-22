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
    echo json_encode(["success" => false, "message" => "DB connection failed."]);
    exit;
}

$r = $conn->query("SHOW COLUMNS FROM `clinics` LIKE 'area'");
if ($r && $r->num_rows == 0) {
    $conn->query("ALTER TABLE `clinics` ADD COLUMN `area` VARCHAR(100) NOT NULL DEFAULT ''");
}
$rDel = $conn->query("SHOW COLUMNS FROM `clinics` LIKE 'is_deleted'");
if ($rDel && $rDel->num_rows == 0) {
    $conn->query("ALTER TABLE `clinics` ADD COLUMN `is_deleted` TINYINT(1) NOT NULL DEFAULT 0");
}

$data = json_decode(file_get_contents("php://input"), true);
$name = trim($data['name'] ?? '');
$address = trim($data['address'] ?? '');
$phone = trim($data['phone'] ?? '');
$map_url = trim($data['map_url'] ?? '');
$lat = (float)($data['lat'] ?? 0.0);
$lng = (float)($data['lng'] ?? 0.0);
$area = trim($data['area'] ?? '');
$added_by = (int)($data['added_by'] ?? 0);

if (empty($name) || $lat == 0.0 || $lng == 0.0) {
    echo json_encode(["success" => false, "message" => "Name and valid coordinates required."]);
    exit;
}

$stmt = $conn->prepare("INSERT INTO clinics (name, lat, lng, address, phone, map_url, area, added_by, is_deleted) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)");
$stmt->bind_param("sddssssi", $name, $lat, $lng, $address, $phone, $map_url, $area, $added_by);

if ($stmt->execute()) {
    $newId = $conn->insert_id;
    echo json_encode([
        "success" => true,
        "message" => "Clinic added!",
        "clinic" => [
            "id" => $newId,
            "name" => $name,
            "lat" => $lat,
            "lng" => $lng,
            "address" => $address,
            "phone" => $phone,
            "map_url" => $map_url,
            "area" => $area,
            "added_by" => $added_by
        ]
    ]);
} else {
    echo json_encode(["success" => false, "message" => "Failed to add clinic: " . $conn->error]);
}

$stmt->close();
$conn->close();
?>
