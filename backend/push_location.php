<?php
error_reporting(0);
ini_set('display_errors', 0);
date_default_timezone_set('Asia/Kolkata');

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE");
header("Access-Control-Allow-Headers: *");
header("Content-Type: application/json; charset=UTF-8");

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { exit(0); }

require_once __DIR__ . '/performance_engine.php';

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

ensure_performance_schema($conn);

$raw  = file_get_contents("php://input");
$data = json_decode($raw, true);

if (!$data) {
    echo json_encode(["success" => false, "message" => "Invalid JSON payload"]);
    exit;
}

$userId        = isset($data['user_id'])        ? intval($data['user_id'])         : 0;
$taskId        = isset($data['task_id'])        ? intval($data['task_id'])         : 0;
$salesRepName  = isset($data['sales_rep_name']) ? trim($data['sales_rep_name'])    : '';
$lat           = isset($data['lat'])            ? floatval($data['lat'])           : null;
$lng           = isset($data['lng'])            ? floatval($data['lng'])           : null;

if ($userId <= 0 || $taskId <= 0 || $lat === null || $lng === null || ($lat == 0.0 && $lng == 0.0)) {
    echo json_encode(["success" => false, "message" => "Invalid parameters. user_id, task_id, and valid GPS coordinates are required."]);
    exit;
}

try {
    // ── Strict Server-Side Validation ───────────────────────────────────────────
    // 1. Task exists, belongs to this Sales Rep, and is currently IN PROGRESS
    $stmt = $conn->prepare("SELECT id, user_id, sales_rep_name, status, doctor_name, clinic_name, clinic_address, clinic_lat, clinic_lng, destination_reached_at, target_deadline_at, target_duration_seconds, time_inside_destination_seconds, is_inside_destination, last_location_update FROM tasks WHERE id = ? AND user_id = ?");
    $stmt->bind_param("ii", $taskId, $userId);
    $stmt->execute();
    $res = $stmt->get_result();
    $task = $res->fetch_assoc();
    $stmt->close();

    if (!$task) {
        echo json_encode(["success" => false, "message" => "Task #$taskId not found or does not belong to user #$userId."]);
        $conn->close();
        exit;
    }

    if ($task['status'] !== 'in_progress') {
        echo json_encode(["success" => false, "message" => "Task #$taskId is not currently in progress (status: {$task['status']}). Location push rejected."]);
        $conn->close();
        exit;
    }

    if (empty($salesRepName)) {
        $salesRepName = $task['sales_rep_name'] ?? 'Sales Rep';
    }

    $clinicLat = floatval($task['clinic_lat'] ?? 0);
    $clinicLng = floatval($task['clinic_lng'] ?? 0);
    $distanceMeters = null;
    $isInside = 0;

    if ($clinicLat != 0.0 && $clinicLng != 0.0) {
        $rawDist = haversineDistanceMeters($lat, $lng, $clinicLat, $clinicLng);
        $distanceMeters = round($rawDist, 2);
        // STRICT RULE: <= 15.0m is inside, >= 15.01m is outside
        $isInside = ($distanceMeters <= 15.0) ? 1 : 0;
    }

    $nowKolkata = new DateTime('now', new DateTimeZone('Asia/Kolkata'));
    $nowSql     = $nowKolkata->format('Y-m-d H:i:s');
    $nowTs      = $nowKolkata->getTimestamp();

    $destReachedAt    = $task['destination_reached_at'];
    $targetDeadlineAt = $task['target_deadline_at'];
    $targetDurationSec = intval($task['target_duration_seconds'] ?? 300) ?: 300;
    $insideSec        = intval($task['time_inside_destination_seconds'] ?? 0);
    $justReached      = false;

    // ── Strict 15.0m Destination Entry Detection & 5-Minute Timer Start ────────
    if ($isInside === 1) {
        if (empty($destReachedAt)) {
            // First entry within <= 15.0m: Start 5-minute target timer
            $destReachedAt = $nowSql;
            $deadlineDt = (clone $nowKolkata)->modify('+300 seconds');
            $targetDeadlineAt = $deadlineDt->format('Y-m-d H:i:s');
            $targetDurationSec = 300;
            $justReached = true;
            $insideSec = 1;
        } else {
            // Increment inside seconds based on time elapsed since last location ping
            if (!empty($task['last_location_update'])) {
                $lastUpdTs = strtotime($task['last_location_update']);
                $diff = $nowTs - $lastUpdTs;
                if ($diff > 0 && $diff <= 30) {
                    $insideSec += $diff;
                } else {
                    $insideSec += 1;
                }
            } else {
                $insideSec += 1;
            }
        }
    }

    // 2. Insert tracking location record into clinic_location_tracking table
    $address    = $task['clinic_address'] ?? '';
    $doctorName = $task['doctor_name'] ?? '';
    $clinicName = $task['clinic_name'] ?? '';
    $locType    = $justReached ? 'destination_reached' : 'task_tracking';
    $notes      = $justReached
        ? "Reached destination within 15m ({$distanceMeters}m) for Dr. $doctorName ($clinicName) - 5-min target started"
        : "Live tracking ({$distanceMeters}m, " . ($isInside ? "WITHIN 15M" : "OUTSIDE 15M") . ") for Task #$taskId - Dr. $doctorName ($clinicName)";

    $ins = $conn->prepare(
        "INSERT INTO clinic_location_tracking (task_id, user_id, sales_rep_name, doctor_name, clinic_name, clinic_address, type, lat, lng, notes)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
    );
    $ins->bind_param("iisssssdds", $taskId, $userId, $salesRepName, $doctorName, $clinicName, $address, $locType, $lat, $lng, $notes);

    if ($ins->execute()) {
        $ins->close();

        // 3. Update task last known location & destination monitoring state
        if ($justReached) {
            $upd = $conn->prepare("UPDATE tasks SET 
                last_latitude = ?, 
                last_longitude = ?, 
                last_location_update = NOW(),
                last_destination_distance_meters = ?,
                destination_distance_meters = ?,
                is_inside_destination = 1,
                time_inside_destination_seconds = ?,
                destination_reached_at = ?,
                target_deadline_at = ?,
                target_duration_seconds = 300,
                destination_reached_lat = ?,
                destination_reached_lng = ?,
                destination_reached_distance_meters = ?
                WHERE id = ?");
            $upd->bind_param("ddddisssdddi", $lat, $lng, $distanceMeters, $distanceMeters, $insideSec, $destReachedAt, $targetDeadlineAt, $lat, $lng, $distanceMeters, $taskId);
        } else {
            $upd = $conn->prepare("UPDATE tasks SET 
                last_latitude = ?, 
                last_longitude = ?, 
                last_location_update = NOW(),
                last_destination_distance_meters = ?,
                destination_distance_meters = ?,
                is_inside_destination = ?,
                time_inside_destination_seconds = ?
                WHERE id = ?");
            $upd->bind_param("ddddiii", $lat, $lng, $distanceMeters, $distanceMeters, $isInside, $insideSec, $taskId);
        }
        $upd->execute();
        $upd->close();

        // Calculate live timer countdown / overtime
        $isOvertime = false;
        $remainingSeconds = null;
        $overtimeSeconds = 0;

        if (!empty($targetDeadlineAt)) {
            $deadlineTs = strtotime($targetDeadlineAt);
            $diff = $deadlineTs - $nowTs;
            if ($diff >= 0) {
                $remainingSeconds = $diff;
            } else {
                $isOvertime = true;
                $remainingSeconds = 0;
                $overtimeSeconds = abs($diff);
            }
        }

        echo json_encode([
            "success"                          => true,
            "message"                          => "Tracking location recorded for Task #$taskId.",
            "task_id"                          => $taskId,
            "distance_meters"                  => $distanceMeters,
            "is_inside_destination"            => ($isInside === 1),
            "destination_reached"              => !empty($destReachedAt),
            "destination_reached_at"           => $destReachedAt,
            "target_deadline_at"               => $targetDeadlineAt,
            "target_duration_seconds"          => $targetDurationSec,
            "time_inside_destination_seconds"  => $insideSec,
            "is_overtime"                      => $isOvertime,
            "remaining_seconds"                => $remainingSeconds,
            "overtime_seconds"                 => $overtimeSeconds
        ]);
    } else {
        echo json_encode(["success" => false, "message" => "DB insert error: " . $ins->error]);
        $ins->close();
    }
} catch (Throwable $e) {
    echo json_encode(["success" => false, "message" => "Server error: " . $e->getMessage()]);
}

$conn->close();
?>
