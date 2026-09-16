<?php
error_reporting(0);
ini_set('display_errors', 0);

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE");
header("Access-Control-Allow-Headers: *");
header('Content-Type: application/json; charset=UTF-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { exit(0); }

// Geodesic distance calculation in meters using Haversine formula
function haversineDistanceMeters($lat1, $lon1, $lat2, $lon2) {
    $earthRadius = 6371000; // Earth radius in meters
    $dLat = deg2rad($lat2 - $lat1);
    $dLon = deg2rad($lon2 - $lon1);
    $a = sin($dLat / 2) * sin($dLat / 2) +
         cos(deg2rad($lat1)) * cos(deg2rad($lat2)) *
         sin($dLon / 2) * sin($dLon / 2);
    $c = 2 * atan2(sqrt($a), sqrt(1 - $a));
    return $earthRadius * $c;
}

$conn = new mysqli("localhost", "root", "", "medsafe_db");
if ($conn->connect_error) {
    echo json_encode(["success" => false, "message" => "DB connection failed."]);
    exit;
}

$data = json_decode(file_get_contents("php://input"), true);
if (!is_array($data)) {
    $data = $_POST;
}

$task_id       = intval($data['task_id'] ?? 0);
$user_id       = intval($data['user_id'] ?? 0);
$sales_rep_name= trim($data['sales_rep_name'] ?? '');
$status        = trim($data['status'] ?? 'completed');
$checkout_type = trim($data['checkout_type'] ?? '');

// Coordinates
$checkout_lat  = isset($data['checkout_lat']) ? floatval($data['checkout_lat']) : (isset($data['lat']) ? floatval($data['lat']) : null);
$checkout_lng  = isset($data['checkout_lng']) ? floatval($data['checkout_lng']) : (isset($data['lng']) ? floatval($data['lng']) : null);
$dest_lat      = isset($data['destination_lat']) ? floatval($data['destination_lat']) : null;
$dest_lng      = isset($data['destination_lng']) ? floatval($data['destination_lng']) : null;

// Timestamps & durations
$checkout_date = trim($data['checkout_date'] ?? date('Y-m-d'));
$checkout_time = trim($data['checkout_time'] ?? date('H:i:s'));
$checkout_dt   = trim($data['checkout_datetime'] ?? date('Y-m-d H:i:s'));
$stable_sec    = isset($data['stable_duration_seconds']) ? intval($data['stable_duration_seconds']) : 60;

if (!$task_id) {
    echo json_encode(["success" => false, "message" => "task_id is required."]);
    exit;
}

// ── TRANSACTION BLOCK ────────────────────────────────────────────────────────
$conn->begin_transaction();

try {
    // 1. Fetch current task state with row lock
    $stmt = $conn->prepare("SELECT * FROM tasks WHERE id = ? FOR UPDATE");
    $stmt->bind_param("i", $task_id);
    $stmt->execute();
    $result = $stmt->get_result();
    $task = $result->fetch_assoc();
    $stmt->close();

    if (!$task) {
        $conn->rollback();
        echo json_encode(["success" => false, "message" => "Task #$task_id not found."]);
        exit;
    }

    // 2. Duplicate Checkout Protection
    if ($task['status'] === 'completed') {
        $conn->commit();
        echo json_encode([
            "success"           => true,
            "already_completed" => true,
            "message"           => "Task is already completed. Original record preserved.",
            "task_id"           => $task_id,
            "status"            => "completed",
            "checked_out_at"    => $task['checked_out_at'] ?? $task['updated_at'] ?? ''
        ]);
        exit;
    }

    $isAutoCheckout = (strtoupper($checkout_type) === 'AUTO');

    // 3. Fall back destination coordinates to task record if not provided in payload
    if ($dest_lat === null && isset($task['clinic_lat'])) {
        $dest_lat = floatval($task['clinic_lat']);
    }
    if ($dest_lng === null && isset($task['clinic_lng'])) {
        $dest_lng = floatval($task['clinic_lng']);
    }

    $distanceMeters = null;

    // Validate location coordinates for any task completion (AUTO and MANUAL)
    if ($status === 'completed') {
        // Validate coordinates
        if ($checkout_lat === null || $checkout_lng === null || $dest_lat === null || $dest_lng === null || $checkout_lat == 0.0 || $dest_lat == 0.0) {
            $conn->rollback();
            echo json_encode([
                "success" => false,
                "message" => "You are not in the Doctor's Clinic. Valid checkout coordinates and destination coordinates are required."
            ]);
            exit;
        }

        // 4. Backend Geodesic Distance Verification (Haversine)
        $rawDistance = haversineDistanceMeters($checkout_lat, $checkout_lng, $dest_lat, $dest_lng);
        $distanceMeters = round($rawDistance, 2);

        // Strict 20-meter radius validation (with tiny 0.05m floating point tolerance)
        if ($distanceMeters > 20.05) {
            $conn->rollback();
            echo json_encode([
                "success"         => false,
                "message"         => "You are not in the Doctor's Clinic. Checkout location ($distanceMeters m) is outside the required 20-meter destination radius.",
                "distance_meters" => $distanceMeters,
                "required_radius" => 20.0
            ]);
            exit;
        }
    }

    // 5. Update Task Record Transactionally
    $updateSql = "UPDATE tasks SET 
        status = ?,
        checked_out_at = ?,
        checkout_date = ?,
        checkout_time = ?,
        checkout_type = ?,
        checkout_lat = ?,
        checkout_lng = ?,
        destination_distance_meters = ?,
        stable_duration_seconds = ?,
        last_latitude = ?,
        last_longitude = ?,
        last_location_update = NOW(),
        updated_at = NOW()
        WHERE id = ?";

    $cType = $isAutoCheckout ? 'AUTO' : ($checkout_type ?: 'manual');
    $uStatus = 'completed';

    $updStmt = $conn->prepare($updateSql);
    $updStmt->bind_param(
        "sssssddddddi",
        $uStatus,
        $checkout_dt,
        $checkout_date,
        $checkout_time,
        $cType,
        $checkout_lat,
        $checkout_lng,
        $distanceMeters,
        $stable_sec,
        $checkout_lat,
        $checkout_lng,
        $task_id
    );

    $executed = $updStmt->execute();
    $updStmt->close();

    if (!$executed) {
        $conn->rollback();
        echo json_encode(["success" => false, "message" => "Database update failed: " . $conn->error]);
        exit;
    }

    // Commit Transaction
    $conn->commit();

    echo json_encode([
        "success"                    => true,
        "already_completed"          => false,
        "message"                    => "Task automatically checked out and recorded in database!",
        "task_id"                    => $task_id,
        "status"                     => "completed",
        "checkout_type"              => $cType,
        "checkout_lat"               => $checkout_lat,
        "checkout_lng"               => $checkout_lng,
        "destination_distance_meters"=> $distanceMeters,
        "stable_duration_seconds"    => $stable_sec,
        "checkout_date"              => $checkout_date,
        "checkout_time"              => $checkout_time,
        "checked_out_at"             => $checkout_dt
    ]);

} catch (Exception $e) {
    $conn->rollback();
    echo json_encode([
        "success" => false,
        "message" => "Transaction error: " . $e->getMessage()
    ]);
}

$conn->close();
?>
