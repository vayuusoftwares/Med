<?php
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE");
header("Access-Control-Allow-Headers: *");
header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
  echo json_encode(["status" => "ok"]);
  exit;
}

$servername = "localhost";
$username = "root";
$password = "";
$dbname = "medsafe_db";

// Create connection
$conn = new mysqli($servername, $username, $password, $dbname);

// Check connection
if ($conn->connect_error) {
  die(json_encode(["error" => "Connection failed: " . $conn->connect_error]));
}

$user_id = isset($_GET['user_id']) ? (int)$_GET['user_id'] : (isset($_POST['user_id']) ? (int)$_POST['user_id'] : 0);
$role = isset($_GET['role']) ? trim($_GET['role']) : (isset($_POST['role']) ? trim($_POST['role']) : '');

// Ensure area column exists in tables
$conn->query("ALTER TABLE doctors ADD COLUMN IF NOT EXISTS area VARCHAR(100) NOT NULL DEFAULT ''");
$conn->query("ALTER TABLE clinics ADD COLUMN IF NOT EXISTS area VARCHAR(100) NOT NULL DEFAULT ''");
$conn->query("ALTER TABLE tasks ADD COLUMN IF NOT EXISTS area VARCHAR(100) NOT NULL DEFAULT ''");

// Fetch Doctors (excluding soft-deleted)
if ($role === 'sales_rep' && $user_id > 0) {
  $stmt_doc = $conn->prepare("SELECT id, name, speciality, phone, area, added_by FROM doctors WHERE (is_deleted = 0 OR is_deleted IS NULL) AND (added_by = 0 OR added_by IS NULL OR added_by = ?) ORDER BY name ASC");
  $stmt_doc->bind_param("i", $user_id);
  $stmt_doc->execute();
  $result_doctors = $stmt_doc->get_result();
} else {
  $sql_doctors = "SELECT id, name, speciality, phone, area, added_by FROM doctors WHERE (is_deleted = 0 OR is_deleted IS NULL) ORDER BY name ASC";
  $result_doctors = $conn->query($sql_doctors);
}

$doctors = array();
if ($result_doctors && $result_doctors->num_rows > 0) {
  while($row = $result_doctors->fetch_assoc()) {
    $doctors[] = array(
      "id" => (int)($row["id"] ?? 0),
      "name" => $row["name"],
      "speciality" => $row["speciality"] ?? "General Physician",
      "phone" => $row["phone"] ?? "",
      "area" => $row["area"] ?? "",
      "added_by" => (int)($row["added_by"] ?? 0)
    );
  }
}

// Fetch Clinics (excluding soft-deleted)
if ($role === 'sales_rep' && $user_id > 0) {
  $stmt_clin = $conn->prepare("SELECT id, name, lat, lng, address, phone, map_url, area, added_by FROM clinics WHERE (is_deleted = 0 OR is_deleted IS NULL) AND (added_by = 0 OR added_by IS NULL OR added_by = ?) ORDER BY name ASC");
  $stmt_clin->bind_param("i", $user_id);
  $stmt_clin->execute();
  $result_clinics = $stmt_clin->get_result();
} else {
  $sql_clinics = "SELECT id, name, lat, lng, address, phone, map_url, area, added_by FROM clinics WHERE (is_deleted = 0 OR is_deleted IS NULL) ORDER BY name ASC";
  $result_clinics = $conn->query($sql_clinics);
}

$clinics = array();
if ($result_clinics && $result_clinics->num_rows > 0) {
  while($row = $result_clinics->fetch_assoc()) {
    $clinics[] = array(
      "id" => (int)($row["id"] ?? 0),
      "name" => $row["name"],
      "lat" => (float)$row["lat"],
      "lng" => (float)$row["lng"],
      "address" => $row["address"] ?? "",
      "phone" => $row["phone"] ?? "",
      "map_url" => $row["map_url"] ?? "",
      "area" => $row["area"] ?? "",
      "added_by" => (int)($row["added_by"] ?? 0)
    );
  }
}

// Fetch known Doctor + Clinic combinations from tasks
$combinations = array();
$sql_combos = "SELECT DISTINCT doctor_name, clinic_name, clinic_lat, clinic_lng, clinic_address, area FROM tasks WHERE doctor_name != '' AND clinic_name != '' ORDER BY id DESC";
$result_combos = $conn->query($sql_combos);
if ($result_combos && $result_combos->num_rows > 0) {
  while($row = $result_combos->fetch_assoc()) {
    $combinations[] = array(
      "doctor_name" => $row["doctor_name"],
      "clinic_name" => $row["clinic_name"],
      "clinic_lat" => (float)$row["clinic_lat"],
      "clinic_lng" => (float)$row["clinic_lng"],
      "clinic_address" => $row["clinic_address"] ?? "",
      "area" => $row["area"] ?? ""
    );
  }
}

// Fetch deleted areas to exclude
$conn->query("CREATE TABLE IF NOT EXISTS deleted_areas (
    id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    area VARCHAR(100) NOT NULL UNIQUE,
    deleted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
)");
$deletedAreas = array();
$resDel = $conn->query("SELECT area FROM deleted_areas");
if ($resDel) {
  while ($r = $resDel->fetch_assoc()) {
    $deletedAreas[] = strtolower(trim($r['area']));
  }
}

// Fetch distinct areas from areas table, doctors, clinics, and tasks
$areasSet = array("All Areas");
$defaultAreas = array("Chennai", "Villupuram", "Cuddalore", "Tindivanam");
foreach ($defaultAreas as $da) {
  if (!in_array($da, $areasSet) && !in_array(strtolower($da), $deletedAreas)) {
    $areasSet[] = $da;
  }
}

$resArea0 = $conn->query("SELECT DISTINCT name FROM areas WHERE name IS NOT NULL AND name != ''");
if ($resArea0) {
  while ($r = $resArea0->fetch_assoc()) {
    $a = trim($r['name']);
    if (!empty($a) && !in_array($a, $areasSet) && !in_array(strtolower($a), $deletedAreas)) {
      $areasSet[] = $a;
    }
  }
}

$resArea1 = $conn->query("SELECT DISTINCT area FROM doctors WHERE area IS NOT NULL AND area != ''");
if ($resArea1) {
  while ($r = $resArea1->fetch_assoc()) {
    $a = trim($r['area']);
    if (!empty($a) && !in_array($a, $areasSet) && !in_array(strtolower($a), $deletedAreas)) {
      $areasSet[] = $a;
    }
  }
}
$resArea2 = $conn->query("SELECT DISTINCT area FROM clinics WHERE area IS NOT NULL AND area != ''");
if ($resArea2) {
  while ($r = $resArea2->fetch_assoc()) {
    $a = trim($r['area']);
    if (!empty($a) && !in_array($a, $areasSet) && !in_array(strtolower($a), $deletedAreas)) {
      $areasSet[] = $a;
    }
  }
}
$resArea3 = $conn->query("SELECT DISTINCT area FROM tasks WHERE area IS NOT NULL AND area != ''");
if ($resArea3) {
  while ($r = $resArea3->fetch_assoc()) {
    $a = trim($r['area']);
    if (!empty($a) && !in_array($a, $areasSet) && !in_array(strtolower($a), $deletedAreas)) {
      $areasSet[] = $a;
    }
  }
}

$conn->close();

// Return combined JSON
echo json_encode(array(
  "areas" => $areasSet,
  "doctors" => $doctors,
  "clinics" => $clinics,
  "combinations" => $combinations
));
?>

