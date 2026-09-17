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

$conn->query("CREATE TABLE IF NOT EXISTS areas (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    added_by INT UNSIGNED NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
)");

$conn->query("CREATE TABLE IF NOT EXISTS deleted_areas (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    area VARCHAR(100) NOT NULL UNIQUE,
    deleted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
)");

$rawInput = file_get_contents("php://input");
$data = json_decode($rawInput, true);
if (!$data) {
    $data = $_POST;
}
$name = trim($data['name'] ?? $data['area'] ?? '');
$added_by = (int)($data['added_by'] ?? 0);

if (empty($name) || strcasecmp($name, 'All Areas') === 0) {
    echo json_encode(["success" => false, "message" => "Valid Area / Division name is required."]);
    exit;
}

// Remove from deleted_areas if it was previously deleted
$stmtDel = $conn->prepare("DELETE FROM deleted_areas WHERE LOWER(area) = LOWER(?)");
$stmtDel->bind_param("s", $name);
$stmtDel->execute();
$stmtDel->close();

$stmt = $conn->prepare("INSERT INTO areas (name, added_by) VALUES (?, ?) ON DUPLICATE KEY UPDATE added_by = VALUES(added_by)");
$stmt->bind_param("si", $name, $added_by);

if ($stmt->execute()) {
    echo json_encode([
        "success" => true,
        "message" => "Area added successfully!",
        "area" => $name
    ]);
} else {
    echo json_encode(["success" => false, "message" => "Failed to add area: " . $conn->error]);
}

$stmt->close();
$conn->close();
?>
