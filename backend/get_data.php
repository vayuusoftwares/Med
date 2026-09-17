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

// Fetch Doctors (excluding soft-deleted)
if ($role === 'sales_rep' && $user_id > 0) {
  $stmt_doc = $conn->prepare("SELECT id, name, speciality, phone, added_by FROM doctors WHERE (is_deleted = 0 OR is_deleted IS NULL) AND (added_by = 0 OR added_by IS NULL OR added_by = ?) ORDER BY name ASC");
  $stmt_doc->bind_param("i", $user_id);
  $stmt_doc->execute();
  $result_doctors = $stmt_doc->get_result();
} else {
  $sql_doctors = "SELECT id, name, speciality, phone, added_by FROM doctors WHERE (is_deleted = 0 OR is_deleted IS NULL) ORDER BY name ASC";
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
      "added_by" => (int)($row["added_by"] ?? 0)
    );
  }
}

// Fetch Clinics (excluding soft-deleted)
if ($role === 'sales_rep' && $user_id > 0) {
  $stmt_clin = $conn->prepare("SELECT id, name, lat, lng, address, phone, map_url, added_by FROM clinics WHERE (is_deleted = 0 OR is_deleted IS NULL) AND (added_by = 0 OR added_by IS NULL OR added_by = ?) ORDER BY name ASC");
  $stmt_clin->bind_param("i", $user_id);
  $stmt_clin->execute();
  $result_clinics = $stmt_clin->get_result();
} else {
  $sql_clinics = "SELECT id, name, lat, lng, address, phone, map_url, added_by FROM clinics WHERE (is_deleted = 0 OR is_deleted IS NULL) ORDER BY name ASC";
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
      "added_by" => (int)($row["added_by"] ?? 0)
    );
  }
}

// Fetch known Doctor + Clinic combinations from tasks
$combinations = array();
$sql_combos = "SELECT DISTINCT doctor_name, clinic_name, clinic_lat, clinic_lng, clinic_address FROM tasks WHERE doctor_name != '' AND clinic_name != '' ORDER BY id DESC";
$result_combos = $conn->query($sql_combos);
if ($result_combos && $result_combos->num_rows > 0) {
  while($row = $result_combos->fetch_assoc()) {
    $combinations[] = array(
      "doctor_name" => $row["doctor_name"],
      "clinic_name" => $row["clinic_name"],
      "clinic_lat" => (float)$row["clinic_lat"],
      "clinic_lng" => (float)$row["clinic_lng"],
      "clinic_address" => $row["clinic_address"] ?? ""
    );
  }
}

$conn->close();

// Return combined JSON
echo json_encode(array(
  "doctors" => $doctors,
  "clinics" => $clinics,
  "combinations" => $combinations
));
?>

