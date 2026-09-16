<?php
// Suppress all PHP warnings/notices/xdebug output — only return clean JSON
error_reporting(0);
ini_set('display_errors', 0);

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE");
header("Access-Control-Allow-Headers: *");
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { exit(0); }

$conn = new mysqli("localhost", "root", "", "medsafe_db");
if ($conn->connect_error) {
    echo json_encode(["success" => false, "message" => "Connection failed."]);
    exit;
}

$data     = json_decode(file_get_contents("php://input"), true);
$email    = strtolower(trim($data['email'] ?? ''));
$password = $data['password'] ?? '';
$role     = $data['role'] ?? 'sales_rep';

if (!$email || !$password) {
    echo json_encode(["success" => false, "message" => "Email and password are required."]);
    exit;
}

$stmt = $conn->prepare("SELECT id, name, email, phone, password_hash, role, created_at FROM users WHERE email = ? AND role = ?");
$stmt->bind_param("ss", $email, $role);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    echo json_encode(["success" => false, "message" => "Invalid credentials."]);
    exit;
}

$user = $result->fetch_assoc();

if (!password_verify($password, $user['password_hash'])) {
    echo json_encode(["success" => false, "message" => "Invalid credentials."]);
    exit;
}

$roleLabel = $user['role'] === 'admin' ? 'Administrator' : 'Sales Representative';
echo json_encode([
    "success" => true,
    "message" => "Login successful!",
    "data" => [
        "user" => [
            "id"         => (int)$user['id'],
            "name"       => $user['name'],
            "email"      => $user['email'],
            "phone"      => $user['phone'],
            "role"       => $user['role'],
            "role_label" => $roleLabel,
            "is_active"  => true,
            "created_at" => $user['created_at']
        ],
        "access_token" => "wamp_token_" . $user['id'] . "_" . time()
    ]
]);

$stmt->close();
$conn->close();
?>
