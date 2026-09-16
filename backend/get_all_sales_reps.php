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

$conn = new mysqli("localhost", "root", "", "medsafe_db");
if ($conn->connect_error) {
    echo json_encode(["success" => false, "message" => "DB connection failed: " . $conn->connect_error]);
    exit;
}

ensure_performance_schema($conn);

$sql = "SELECT id, name, email, phone, role, created_at FROM users WHERE role = 'sales_rep' ORDER BY id ASC";
$result = $conn->query($sql);

$reps = [];

if ($result && $result->num_rows > 0) {
    while ($row = $result->fetch_assoc()) {
        $userId = (int)$row['id'];
        $repName = trim($row['name']);
        
        // Fetch last attendance record matching sales_rep_name or user_id
        $attStmt = $conn->prepare("SELECT type, lat, lng, created_at FROM attendance_history WHERE LOWER(sales_rep_name) = LOWER(?) OR user_id = ? ORDER BY id DESC LIMIT 1");
        $attStmt->bind_param("si", $repName, $userId);
        $attStmt->execute();
        $attRes = $attStmt->get_result();
        
        $lastLat = null;
        $lastLng = null;
        $lastAccuracy = 10.0;
        $lastPingAt = null;
        $isOnline = false;

        if ($attRes && $attRes->num_rows > 0) {
            $att = $attRes->fetch_assoc();
            $lastLat = (float)$att['lat'];
            $lastLng = (float)$att['lng'];
            $lastPingAt = date('c', strtotime($att['created_at']));
            
            $type = isset($att['type']) ? strtolower(trim($att['type'])) : '';
            $isOnline = ($type === 'check_in');
        }
        $attStmt->close();

        // Fetch this rep's tasks to calculate performance summary
        $tStmt = $conn->prepare("SELECT t.*, p.assigned_date_time, p.start_date_time, p.deadline_date_time, p.end_date_time, p.total_duration, p.performance_status, p.late_by, p.points_earned 
                                 FROM tasks t 
                                 LEFT JOIN sales_rep_performance p ON t.id = p.task_id 
                                 WHERE t.user_id = ? OR LOWER(t.sales_rep_name) = LOWER(?)");
        $tStmt->bind_param("is", $userId, $repName);
        $tStmt->execute();
        $tRes = $tStmt->get_result();
        $repEvaluatedTasks = [];
        if ($tRes && $tRes->num_rows > 0) {
            while ($tRow = $tRes->fetch_assoc()) {
                $repEvaluatedTasks[] = evaluate_task_performance($tRow);
            }
        }
        $tStmt->close();

        $perfSummary = calculate_sales_rep_summary($repEvaluatedTasks);

        $reps[] = [
            "id"                   => $userId,
            "name"                 => $row['name'],
            "email"                => $row['email'],
            "phone"                => $row['phone'],
            "is_active"            => true,
            "created_at"           => date('c', strtotime($row['created_at'])),
            "last_lat"             => $lastLat,
            "last_lng"             => $lastLng,
            "last_accuracy"        => $lastAccuracy,
            "last_ping_at"         => $lastPingAt,
            "is_online"            => $isOnline,
            "total_tasks"          => $perfSummary['total_tasks'],
            "completed_tasks"      => $perfSummary['completed_tasks'],
            "pending_tasks"        => $perfSummary['pending_tasks'],
            "green_tasks"          => $perfSummary['green_tasks'],
            "red_tasks"            => $perfSummary['red_tasks'],
            "overdue_tasks"        => $perfSummary['overdue_tasks'],
            "on_track_tasks"       => $perfSummary['on_track_tasks'],
            "on_time_percentage"   => $perfSummary['on_time_percentage'],
            "performance_score"    => $perfSummary['performance_score'],
            "score_display"        => $perfSummary['score_display'],
            "has_performance_data" => $perfSummary['has_data'],
        ];
    }
}

echo json_encode([
    "success" => true,
    "count"   => count($reps),
    "reps"    => $reps
]);

$conn->close();
?>
