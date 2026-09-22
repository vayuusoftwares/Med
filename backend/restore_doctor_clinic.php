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
$area_names = isset($data['area_names']) && is_array($data['area_names']) ? $data['area_names'] : [];

if (empty($doctor_ids) && empty($clinic_ids) && empty($doctor_names) && empty($clinic_names) && empty($area_names)) {
  echo json_encode(["success" => false, "message" => "No records specified to restore."]);
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

$restored_doctor_ids = [];
$restored_clinic_ids = [];
$restored_area_names = [];

// Ensure columns and tables exist
function ensure_col($conn, $table, $col, $def) {
  $r = $conn->query("SHOW COLUMNS FROM `$table` LIKE '$col'");
  if ($r && $r->num_rows == 0) {
    $conn->query("ALTER TABLE `$table` ADD COLUMN `$col` $def");
  }
}
ensure_col($conn, 'doctors', 'area', "VARCHAR(100) NOT NULL DEFAULT ''");
ensure_col($conn, 'doctors', 'is_deleted', "TINYINT(1) NOT NULL DEFAULT 0");
ensure_col($conn, 'doctors', 'deleted_at', "DATETIME NULL DEFAULT NULL");
ensure_col($conn, 'clinics', 'area', "VARCHAR(100) NOT NULL DEFAULT ''");
ensure_col($conn, 'clinics', 'is_deleted', "TINYINT(1) NOT NULL DEFAULT 0");
ensure_col($conn, 'clinics', 'deleted_at', "DATETIME NULL DEFAULT NULL");
ensure_col($conn, 'tasks', 'area', "VARCHAR(100) NOT NULL DEFAULT ''");

$conn->begin_transaction();

try {
  // Ensure areas table exists
  $conn->query("CREATE TABLE IF NOT EXISTS areas (
      id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      name VARCHAR(100) NOT NULL UNIQUE,
      added_by INT UNSIGNED NOT NULL DEFAULT 0,
      created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
  )");

  // Restore areas
  if (!empty($area_names)) {
    foreach ($area_names as $aName) {
      $area = trim((string)$aName);
      if ($area === '') continue;

      // 1. Remove from deleted_areas
      $stmt = $conn->prepare("DELETE FROM deleted_areas WHERE LOWER(area) = LOWER(?)");
      $stmt->bind_param("s", $area);
      $stmt->execute();
      $stmt->close();

      // 2. Insert back into areas table
      $stmtArea = $conn->prepare("INSERT INTO areas (name, added_by) VALUES (?, ?) ON DUPLICATE KEY UPDATE added_by = VALUES(added_by)");
      $stmtArea->bind_param("si", $area, $user_id);
      $stmtArea->execute();
      $stmtArea->close();

      $restored_area_names[] = $area;
    }
  }

  // Restore doctors by ID
  if (!empty($doctor_ids)) {
    foreach ($doctor_ids as $dId) {
      $id = (int)$dId;
      if ($id <= 0) continue;

      $stmt = $conn->prepare("UPDATE doctors SET is_deleted = 0, deleted_at = NULL WHERE id = ?");
      $stmt->bind_param("i", $id);
      $stmt->execute();
      if ($stmt->affected_rows > 0) {
        $restored_doctor_ids[] = $id;
      }
      $stmt->close();
    }
  }

  // Restore doctors by Name
  if (!empty($doctor_names)) {
    foreach ($doctor_names as $dName) {
      $name = trim((string)$dName);
      if ($name === '') continue;

      $stmt = $conn->prepare("UPDATE doctors SET is_deleted = 0, deleted_at = NULL WHERE name = ?");
      $stmt->bind_param("s", $name);
      $stmt->execute();
      $stmt->close();
    }
  }

  // Restore clinics by ID
  if (!empty($clinic_ids)) {
    foreach ($clinic_ids as $cId) {
      $id = (int)$cId;
      if ($id <= 0) continue;

      $stmt = $conn->prepare("UPDATE clinics SET is_deleted = 0, deleted_at = NULL WHERE id = ?");
      $stmt->bind_param("i", $id);
      $stmt->execute();
      if ($stmt->affected_rows > 0) {
        $restored_clinic_ids[] = $id;
      }
      $stmt->close();
    }
  }

  // Restore clinics by Name
  if (!empty($clinic_names)) {
    foreach ($clinic_names as $cName) {
      $name = trim((string)$cName);
      if ($name === '') continue;

      $stmt = $conn->prepare("UPDATE clinics SET is_deleted = 0, deleted_at = NULL WHERE name = ?");
      $stmt->bind_param("s", $name);
      $stmt->execute();
      $stmt->close();
    }
  }

  $conn->commit();
  $total = max(count($restored_doctor_ids) + count($restored_clinic_ids) + count($restored_area_names), count($doctor_names) + count($clinic_names) + count($area_names));

  echo json_encode([
    "success" => true,
    "message" => "$total record" . ($total === 1 ? "" : "s") . " restored successfully.",
    "restored_doctor_ids" => $restored_doctor_ids,
    "deleted_doctor_ids" => $restored_doctor_ids,
    "deleted_clinic_ids" => $restored_clinic_ids,
    "restored_area_names" => $restored_area_names
  ]);
} catch (Exception $e) {
  $conn->rollback();
  echo json_encode([
    "success" => false,
    "message" => "Failed to restore records: " . $e->getMessage()
  ]);
}

$conn->close();
?>
