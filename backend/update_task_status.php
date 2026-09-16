<?php
error_reporting(0);
ini_set('display_errors', 0);
date_default_timezone_set('Asia/Kolkata');

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE");
header("Access-Control-Allow-Headers: *");
header('Content-Type: application/json; charset=UTF-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { exit(0); }

require_once __DIR__ . '/performance_engine.php';

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

ensure_performance_schema($conn);

$data = json_decode(file_get_contents("php://input"), true);
if (!is_array($data)) {
    $data = $_POST;
}

$task_id       = intval($data['task_id'] ?? 0);
$user_id       = intval($data['user_id'] ?? 0);
$sales_rep_name= trim($data['sales_rep_name'] ?? '');
$requested_status = strtolower(trim($data['status'] ?? 'completed'));
if ($requested_status === 'started') {
    $requested_status = 'in_progress';
}
$checkout_type = trim($data['checkout_type'] ?? '');

// Coordinates
$lat           = isset($data['lat']) ? floatval($data['lat']) : (isset($data['checkout_lat']) ? floatval($data['checkout_lat']) : null);
$lng           = isset($data['lng']) ? floatval($data['lng']) : (isset($data['checkout_lng']) ? floatval($data['checkout_lng']) : null);
$dest_lat      = isset($data['destination_lat']) ? floatval($data['destination_lat']) : null;
$dest_lng      = isset($data['destination_lng']) ? floatval($data['destination_lng']) : null;

// Timestamps & durations in Asia/Kolkata
$nowKolkata    = new DateTime('now', new DateTimeZone('Asia/Kolkata'));
$nowSql        = $nowKolkata->format('Y-m-d H:i:s');
$checkout_date = trim($data['checkout_date'] ?? $nowKolkata->format('Y-m-d'));
$checkout_time = trim($data['checkout_time'] ?? $nowKolkata->format('H:i:s'));
$checkout_dt   = trim($data['checkout_datetime'] ?? $nowSql);
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

    // Security: Validate user ownership if user_id is provided
    if ($user_id > 0 && intval($task['user_id']) !== $user_id) {
        $conn->rollback();
        echo json_encode(["success" => false, "message" => "Unauthorized. Task does not belong to this Sales Rep."]);
        exit;
    }

    if (empty($sales_rep_name)) {
        $sales_rep_name = $task['sales_rep_name'] ?? 'Sales Rep';
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FLOW A: SALES REP STARTS TASK (status = in_progress)
    // ─────────────────────────────────────────────────────────────────────────
    if ($requested_status === 'in_progress') {
        if ($task['status'] === 'completed') {
            $conn->rollback();
            echo json_encode(["success" => false, "message" => "Task is already completed."]);
            exit;
        }

        if ($lat === null || $lng === null || ($lat == 0.0 && $lng == 0.0)) {
            $conn->rollback();
            echo json_encode(["success" => false, "message" => "Valid real GPS coordinates required to start task."]);
            exit;
        }

        $startDtStr = !empty($task['start_date_time']) ? $task['start_date_time'] : $nowSql;

        $upd = $conn->prepare("UPDATE tasks SET 
            status = 'in_progress',
            start_date_time = COALESCE(start_date_time, ?),
            started_at = COALESCE(started_at, ?),
            source_lat = ?,
            source_lng = ?,
            last_latitude = ?,
            last_longitude = ?,
            last_location_update = NOW(),
            updated_at = NOW()
            WHERE id = ?");
        $upd->bind_param("ssddddi", $startDtStr, $startDtStr, $lat, $lng, $lat, $lng, $task_id);
        $upd->execute();
        $upd->close();

        // Immediately insert FIRST REAL GPS LOCATION into clinic_location_tracking
        $doctorName    = $task['doctor_name'] ?? 'Doctor';
        $clinicName    = $task['clinic_name'] ?? 'Clinic';
        $clinicAddress = $task['clinic_address'] ?? '';
        $startNotes    = "Task #$task_id started for Dr. $doctorName ($clinicName)";

        $insLoc = $conn->prepare("INSERT INTO clinic_location_tracking (task_id, user_id, sales_rep_name, doctor_name, clinic_name, clinic_address, type, lat, lng, notes)
            VALUES (?, ?, ?, ?, ?, ?, 'task_start', ?, ?, ?)");
        $insLoc->bind_param("iissssdds", $task_id, $task['user_id'], $sales_rep_name, $doctorName, $clinicName, $clinicAddress, $lat, $lng, $startNotes);
        $insLoc->execute();
        $insLoc->close();

        // Sync performance
        $task['status'] = 'in_progress';
        $task['start_date_time'] = $startDtStr;
        $task['started_at'] = $startDtStr;
        sync_task_performance_record($conn, $task);

        $conn->commit();

        echo json_encode([
            "success"         => true,
            "status"          => "in_progress",
            "task_id"         => $task_id,
            "start_date_time" => $startDtStr,
            "message"         => "Task started! First location recorded in database."
        ]);
        exit;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FLOW B: SALES REP COMPLETES TASK (status = completed)
    // ─────────────────────────────────────────────────────────────────────────
    if ($requested_status === 'completed') {
        // 2. Duplicate Checkout Protection
        if ($task['status'] === 'completed') {
            $conn->commit();
            $perf = evaluate_task_performance($task);
            echo json_encode([
                "success"            => true,
                "already_completed"  => true,
                "message"            => "Task is already completed. Original record preserved.",
                "task_id"            => $task_id,
                "status"             => "completed",
                "checked_out_at"     => $task['checked_out_at'] ?? $task['updated_at'] ?? '',
                "performance_status" => $perf['performance_status'],
                "late_by"            => $perf['late_by'],
                "points_earned"      => $perf['points_earned'],
                "total_duration"     => $perf['total_duration']
            ]);
            exit;
        }

        $isAutoCheckout = (strtoupper($checkout_type) === 'AUTO');

        // Fall back destination coordinates to task record if not provided in payload
        if ($dest_lat === null && isset($task['clinic_lat'])) {
            $dest_lat = floatval($task['clinic_lat']);
        }
        if ($dest_lng === null && isset($task['clinic_lng'])) {
            $dest_lng = floatval($task['clinic_lng']);
        }

        // Validate coordinates
        if ($lat === null || $lng === null || $dest_lat === null || $dest_lng === null || ($lat == 0.0 && $lng == 0.0) || $dest_lat == 0.0) {
            $conn->rollback();
            echo json_encode([
                "success" => false,
                "message" => "You are not in the Doctor's Clinic. Valid checkout coordinates and destination coordinates are required."
            ]);
            exit;
        }

        // Geodesic Distance Verification (Haversine)
        $rawDistance = haversineDistanceMeters($lat, $lng, $dest_lat, $dest_lng);
        $distanceMeters = round($rawDistance, 2);

        // Strict 15-meter radius validation (15.0m or less allowed; 15.01m or more blocked)
        if ($distanceMeters > 15.0) {
            $conn->rollback();
            echo json_encode([
                "success"         => false,
                "message"         => "You are not in the Doctor's Clinic. Checkout location ($distanceMeters m) is outside the required 15-meter destination radius.",
                "distance_meters" => $distanceMeters,
                "required_radius" => 15.0
            ]);
            exit;
        }

        $cType = $isAutoCheckout ? 'AUTO' : ($checkout_type ?: 'manual');

        // ── 5-Minute Destination Target Timer & Overtime Verification ─────────
        $destReachedAt = $task['destination_reached_at'];
        $targetDeadlineAt = $task['target_deadline_at'];
        $targetDurationSec = intval($task['target_duration_seconds'] ?? 300) ?: 300;
        $insideSec = intval($task['time_inside_destination_seconds'] ?? 0);

        if (empty($destReachedAt)) {
            // First time reaching destination during checkout
            $destReachedAt = $checkout_dt;
            $deadlineDt = (clone $nowKolkata)->modify('+300 seconds');
            $targetDeadlineAt = $deadlineDt->format('Y-m-d H:i:s');
        }

        $nowTs = $nowKolkata->getTimestamp();
        $deadlineTs = strtotime($targetDeadlineAt);
        $overtimeReason = trim($data['overtime_reason'] ?? '');
        $completionResult = 'within_target';
        $overtimeDurationSec = 0;
        $overtimeStartedAt = null;

        if ($deadlineTs && $nowTs > $deadlineTs) {
            // Completed after 5 minutes -> Overtime
            if (empty($overtimeReason)) {
                $conn->rollback();
                echo json_encode([
                    "success"                  => false,
                    "overtime_reason_required" => true,
                    "message"                  => "5-minute destination target exceeded. Please provide reason for overtime.",
                    "distance_meters"          => $distanceMeters,
                    "destination_reached_at"   => $destReachedAt,
                    "target_deadline_at"       => $targetDeadlineAt,
                    "overtime_seconds"         => ($nowTs - $deadlineTs)
                ]);
                exit;
            }
            $completionResult = 'overtime';
            $overtimeDurationSec = max(0, $nowTs - $deadlineTs);
            $overtimeStartedAt = $targetDeadlineAt;
        }

        // Update Task Record Transactionally
        $updateSql = "UPDATE tasks SET 
            status = 'completed',
            end_date_time = ?,
            checked_out_at = ?,
            checkout_date = ?,
            checkout_time = ?,
            checkout_type = ?,
            checkout_lat = ?,
            checkout_lng = ?,
            destination_distance_meters = ?,
            final_distance_meters = ?,
            final_lat = ?,
            final_lng = ?,
            stable_duration_seconds = ?,
            destination_reached_at = COALESCE(destination_reached_at, ?),
            target_deadline_at = COALESCE(target_deadline_at, ?),
            target_duration_seconds = 300,
            is_inside_destination = 1,
            time_inside_destination_seconds = GREATEST(time_inside_destination_seconds, ?),
            completion_result = ?,
            overtime_duration_seconds = ?,
            overtime_reason = ?,
            overtime_started_at = ?,
            last_latitude = ?,
            last_longitude = ?,
            last_location_update = NOW(),
            updated_at = NOW()
            WHERE id = ?";

        $updStmt = $conn->prepare($updateSql);
        $updStmt->bind_param(
            "sssssddddddisssisssddi",
            $checkout_dt,
            $checkout_dt,
            $checkout_date,
            $checkout_time,
            $cType,
            $lat,
            $lng,
            $distanceMeters,
            $distanceMeters,
            $lat,
            $lng,
            $stable_sec,
            $destReachedAt,
            $targetDeadlineAt,
            $insideSec,
            $completionResult,
            $overtimeDurationSec,
            $overtimeReason,
            $overtimeStartedAt,
            $lat,
            $lng,
            $task_id
        );

        $executed = $updStmt->execute();
        $updStmt->close();

        if (!$executed) {
            $conn->rollback();
            echo json_encode(["success" => false, "message" => "Database update failed: " . $conn->error]);
            exit;
        }

        // Insert FINAL LOCATION into clinic_location_tracking
        $doctorName    = $task['doctor_name'] ?? 'Doctor';
        $clinicName    = $task['clinic_name'] ?? 'Clinic';
        $clinicAddress = $task['clinic_address'] ?? '';
        $compNotes     = "Task #$task_id completed for Dr. $doctorName ($cType checkout, $completionResult, final dist: ${distanceMeters}m)";

        $insCompLoc = $conn->prepare("INSERT INTO clinic_location_tracking (task_id, user_id, sales_rep_name, doctor_name, clinic_name, clinic_address, type, lat, lng, notes)
            VALUES (?, ?, ?, ?, ?, ?, 'task_complete', ?, ?, ?)");
        $insCompLoc->bind_param("iissssdds", $task_id, $task['user_id'], $sales_rep_name, $doctorName, $clinicName, $clinicAddress, $lat, $lng, $compNotes);
        $insCompLoc->execute();
        $insCompLoc->close();

        // Record exact performance in sales_rep_performance
        $task['status'] = 'completed';
        $task['end_date_time'] = $checkout_dt;
        $task['checked_out_at'] = $checkout_dt;
        $task['checkout_date'] = $checkout_date;
        $task['checkout_time'] = $checkout_time;
        $task['checkout_type'] = $cType;

        $perf = sync_task_performance_record($conn, $task);

        // Commit Transaction
        $conn->commit();

        echo json_encode([
            "success"                    => true,
            "already_completed"          => false,
            "message"                    => "Task completed and performance recorded in database!",
            "task_id"                    => $task_id,
            "status"                     => "completed",
            "checkout_type"              => $cType,
            "checkout_lat"               => $lat,
            "checkout_lng"               => $lng,
            "destination_distance_meters"=> $distanceMeters,
            "final_distance_meters"      => $distanceMeters,
            "destination_reached_at"     => $destReachedAt,
            "target_deadline_at"         => $targetDeadlineAt,
            "target_duration_seconds"    => 300,
            "completion_result"          => $completionResult,
            "overtime_duration_seconds"  => $overtimeDurationSec,
            "stable_duration_seconds"    => $stable_sec,
            "checkout_date"              => $checkout_date,
            "checkout_time"              => $checkout_time,
            "checked_out_at"             => $checkout_dt,
            "end_date_time"              => $checkout_dt,
            "performance_status"         => $perf['performance_status'] ?? '',
            "late_by"                    => $perf['late_by'] ?? '',
            "points_earned"              => $perf['points_earned'] ?? 0,
            "total_duration"             => $perf['total_duration'] ?? '',
            "deadline_date_time"         => $perf['deadline_date_time'] ?? ''
        ]);
        exit;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // FLOW C: CANCELLED
    // ─────────────────────────────────────────────────────────────────────────
    if ($requested_status === 'cancelled') {
        $upd = $conn->prepare("UPDATE tasks SET status = 'cancelled', updated_at = NOW() WHERE id = ?");
        $upd->bind_param("i", $task_id);
        $upd->execute();
        $upd->close();

        $task['status'] = 'cancelled';
        sync_task_performance_record($conn, $task);

        $conn->commit();
        echo json_encode(["success" => true, "status" => "cancelled", "task_id" => $task_id, "message" => "Task cancelled."]);
        exit;
    }

    $conn->rollback();
    echo json_encode(["success" => false, "message" => "Unsupported status request: $requested_status"]);

} catch (Exception $e) {
    $conn->rollback();
    echo json_encode([
        "success" => false,
        "message" => "Transaction error: " . $e->getMessage()
    ]);
}

$conn->close();
?>
