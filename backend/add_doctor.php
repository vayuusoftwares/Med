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

$r = $conn->query("SHOW COLUMNS FROM `doctors` LIKE 'area'");
if ($r && $r->num_rows == 0) {
    $conn->query("ALTER TABLE `doctors` ADD COLUMN `area` VARCHAR(100) NOT NULL DEFAULT ''");
}
$rDel = $conn->query("SHOW COLUMNS FROM `doctors` LIKE 'is_deleted'");
if ($rDel && $rDel->num_rows == 0) {
    $conn->query("ALTER TABLE `doctors` ADD COLUMN `is_deleted` TINYINT(1) NOT NULL DEFAULT 0");
}

$data = json_decode(file_get_contents("php://input"), true);
$name = trim($data['name'] ?? '');
$speciality = trim($data['speciality'] ?? 'General Physician');
$phone = trim($data['phone'] ?? '');
$area = trim($data['area'] ?? '');
$added_by = (int)($data['added_by'] ?? 0);

if (empty($name)) {
    echo json_encode(["success" => false, "message" => "Doctor name is required."]);
    exit;
}

$stmt = $conn->prepare("INSERT INTO doctors (name, speciality, phone, area, added_by, is_deleted) VALUES (?, ?, ?, ?, ?, 0)");
$stmt->bind_param("ssssi", $name, $speciality, $phone, $area, $added_by);

if ($stmt->execute()) {
    $newId = $conn->insert_id;
    echo json_encode([
        "success" => true,
        "message" => "Doctor added!",
        "doctor" => [
            "id" => $newId,
            "name" => $name,
            "speciality" => $speciality,
            "phone" => $phone,
            "area" => $area,
            "added_by" => $added_by
        ]
    ]);
} else {
    echo json_encode(["success" => false, "message" => "Failed to add doctor: " . $conn->error]);
}

$stmt->close();
$conn->close();
?>
