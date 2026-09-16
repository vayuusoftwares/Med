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

$data          = json_decode(file_get_contents("php://input"), true);
$user_id       = (int)($data['user_id'] ?? 0);
$doctor_name   = trim($data['doctor_name'] ?? '');
$products_json = $data['products_json'] ?? '[]';
$pdf_filename  = trim($data['pdf_filename'] ?? '');

if (!$user_id || !$doctor_name || !$pdf_filename) {
    echo json_encode(["success" => false, "message" => "Missing required fields."]);
    exit;
}

$stmt = $conn->prepare(
    "INSERT INTO order_pdfs (user_id, doctor_name, products_json, pdf_filename) VALUES (?, ?, ?, ?)"
);
$stmt->bind_param("isss", $user_id, $doctor_name, $products_json, $pdf_filename);

if ($stmt->execute()) {
    echo json_encode(["success" => true, "message" => "Order PDF saved!", "id" => $conn->insert_id]);
} else {
    echo json_encode(["success" => false, "message" => "Failed: " . $conn->error]);
}

$stmt->close();
$conn->close();
?>
