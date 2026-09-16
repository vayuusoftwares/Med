<?php
// Suppress PHP warnings/xdebug output — only clean JSON
error_reporting(0);
ini_set('display_errors', 0);

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE");
header("Access-Control-Allow-Headers: *");
header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { exit(0); }

$conn = new mysqli("localhost", "root", "", "medsafe_db");
if ($conn->connect_error) {
    echo json_encode(["success" => false, "message" => "Connection failed: " . $conn->connect_error]);
    exit;
}

$data = json_decode(file_get_contents("php://input"), true);
$name     = trim($data['name'] ?? '');
$email    = strtolower(trim($data['email'] ?? ''));
$phone    = trim($data['phone'] ?? '');
$password = $data['password'] ?? '';
$role     = in_array($data['role'] ?? '', ['sales_rep','admin']) ? $data['role'] : 'sales_rep';

if (!$name || !$email || !$phone || !$password) {
    echo json_encode(["success" => false, "message" => "All fields are required."]);
    exit;
}

// Check duplicate
$stmt = $conn->prepare("SELECT id FROM users WHERE email = ?");
$stmt->bind_param("s", $email);
$stmt->execute();
$stmt->store_result();
if ($stmt->num_rows > 0) {
    echo json_encode(["success" => false, "message" => "Email already registered. Please login."]);
    exit;
}
$stmt->close();

$hash = password_hash($password, PASSWORD_BCRYPT);
$stmt = $conn->prepare("INSERT INTO users (name, email, phone, password_hash, role) VALUES (?, ?, ?, ?, ?)");
$stmt->bind_param("sssss", $name, $email, $phone, $hash, $role);

if ($stmt->execute()) {
    $userId = $conn->insert_id;
    $roleLabel = $role === 'admin' ? 'Administrator' : 'Sales Representative';
    echo json_encode([
        "success" => true,
        "message" => "Registration successful!",
        "data" => [
            "user" => [
                "id"         => $userId,
                "name"       => $name,
                "email"      => $email,
                "phone"      => $phone,
                "role"       => $role,
                "role_label" => $roleLabel,
                "is_active"  => true,
                "created_at" => date('c')
            ],
            "access_token" => "wamp_token_" . $userId . "_" . time()
        ]
    ]);
} else {
    echo json_encode(["success" => false, "message" => "Registration failed: " . $conn->error]);
}

$stmt->close();
$conn->close();
?>
