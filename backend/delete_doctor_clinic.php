<?php
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE");
header("Access-Control-Allow-Headers: *");
header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
  echo json_encode(["status" => "ok"]);
  exit;
}

$rawInput = file_get_contents('php://input');
$data = json_decode($rawInput, true);

if (!$data) {
  $data = $_POST;
}

$user_id = isset($data['user_id']) ? (int)$data['user_id'] : 0;
$role = isset($data['role']) ? trim($data['role']) : 'sales_rep';
$doctor_ids = isset($data['doctor_ids']) && is_array($data['doctor_ids']) ? $data['doctor_ids'] : [];
$clinic_ids = isset($data['clinic_ids']) && is_array($data['clinic_ids']) ? $data['clinic_ids'] : [];

$doctor_names = isset($data['doctor_names']) && is_array($data['doctor_names']) ? $data['doctor_names'] : [];
$clinic_names = isset($data['clinic_names']) && is_array($data['clinic_names']) ? $data['clinic_names'] : [];

if (empty($doctor_ids) && empty($clinic_ids) && empty($doctor_names) && empty($clinic_names)) {
  echo json_encode(["success" => false, "message" => "No records selected for deletion."]);
  exit;
}

$servername = "localhost";
$username = "root";
$password = "";
$dbname = "medsafe_db";

$conn = new mysqli($servername, $username, $password, $dbname);

if ($conn->connect_error) {
  die(json_encode(["success" => false, "message" => "Connection failed: " . $conn->connect_error]));
}

$deleted_doctor_ids = [];
$deleted_clinic_ids = [];

$conn->begin_transaction();

try {
  // Soft delete doctors by ID
  if (!empty($doctor_ids)) {
    foreach ($doctor_ids as $dId) {
      $id = (int)$dId;
      if ($id <= 0) continue;

      $stmt = $conn->prepare("UPDATE doctors SET is_deleted = 1, deleted_at = NOW() WHERE id = ?");
      $stmt->bind_param("i", $id);
      $stmt->execute();
      if ($stmt->affected_rows > 0) {
        $deleted_doctor_ids[] = $id;
      }
      $stmt->close();
    }
  }

  // Soft delete doctors by Name if ID was missing
  if (!empty($doctor_names)) {
    foreach ($doctor_names as $dName) {
      $name = trim((string)$dName);
      if ($name === '') continue;

      $stmt = $conn->prepare("UPDATE doctors SET is_deleted = 1, deleted_at = NOW() WHERE name = ? AND (is_deleted = 0 OR is_deleted IS NULL)");
      $stmt->bind_param("s", $name);
      $stmt->execute();
      $stmt->close();
    }
  }

  // Soft delete clinics by ID
  if (!empty($clinic_ids)) {
    foreach ($clinic_ids as $cId) {
      $id = (int)$cId;
      if ($id <= 0) continue;

      $stmt = $conn->prepare("UPDATE clinics SET is_deleted = 1, deleted_at = NOW() WHERE id = ?");
      $stmt->bind_param("i", $id);
      $stmt->execute();
      if ($stmt->affected_rows > 0) {
        $deleted_clinic_ids[] = $id;
      }
      $stmt->close();
    }
  }

  // Soft delete clinics by Name if ID was missing
  if (!empty($clinic_names)) {
    foreach ($clinic_names as $cName) {
      $name = trim((string)$cName);
      if ($name === '') continue;

      $stmt = $conn->prepare("UPDATE clinics SET is_deleted = 1, deleted_at = NOW() WHERE name = ? AND (is_deleted = 0 OR is_deleted IS NULL)");
      $stmt->bind_param("s", $name);
      $stmt->execute();
      $stmt->close();
    }
  }

  $conn->commit();
  $total = max(count($deleted_doctor_ids) + count($deleted_clinic_ids), count($doctor_names) + count($clinic_names));

  echo json_encode([
    "success" => true,
    "message" => "$total record" . ($total === 1 ? "" : "s") . " deleted successfully.",
    "deleted_doctor_ids" => $deleted_doctor_ids,
    "deleted_clinic_ids" => $deleted_clinic_ids
  ]);
} catch (Exception $e) {
  $conn->rollback();
  echo json_encode([
    "success" => false,
    "message" => "Failed to delete records: " . $e->getMessage()
  ]);
}

$conn->close();
?>
