<?php
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE");
header("Access-Control-Allow-Headers: *");
header('Content-Type: application/json');
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

// Fetch Doctors
$sql_doctors = "SELECT name, speciality FROM doctors";
$result_doctors = $conn->query($sql_doctors);
$doctors = array();

if ($result_doctors && $result_doctors->num_rows > 0) {
  while($row = $result_doctors->fetch_assoc()) {
    $doctors[] = $row;
  }
}

// Fetch Clinics
$sql_clinics = "SELECT name, lat, lng, address FROM clinics";
$result_clinics = $conn->query($sql_clinics);
$clinics = array();

if ($result_clinics && $result_clinics->num_rows > 0) {
  while($row = $result_clinics->fetch_assoc()) {
    $clinics[] = array(
      "name" => $row["name"],
      "lat" => (float)$row["lat"],
      "lng" => (float)$row["lng"],
      "address" => $row["address"]
    );
  }
}

$conn->close();

// Return combined JSON
echo json_encode(array(
  "doctors" => $doctors,
  "clinics" => $clinics
));
?>
