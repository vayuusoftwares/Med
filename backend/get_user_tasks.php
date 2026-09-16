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

$user_id        = isset($_GET['user_id']) ? intval($_GET['user_id']) : 0;
$sales_rep_name = isset($_GET['sales_rep_name']) ? trim($_GET['sales_rep_name']) : '';
$fetchAll       = (isset($_GET['all']) && $_GET['all'] == '1');
$from_date_raw  = isset($_GET['from_date']) ? trim($_GET['from_date']) : '';
$to_date_raw    = isset($_GET['to_date']) ? trim($_GET['to_date']) : '';

function parse_ymd($d) {
    if (empty($d)) return null;
    $d = str_replace('/', '-', $d);
    $ts = strtotime($d);
    return ($ts !== false) ? date('Y-m-d', $ts) : null;
}

$from_date = parse_ymd($from_date_raw);
$to_date   = parse_ymd($to_date_raw);

$dateConditions = [];
$dateTypes = '';
$dateParams = [];

if ($from_date && $to_date) {
    $dateConditions[] = "DATE(COALESCE(t.checkout_date, t.checked_out_at, t.created_at)) >= ? AND DATE(COALESCE(t.checkout_date, t.checked_out_at, t.created_at)) <= ?";
    $dateTypes .= "ss";
    $dateParams[] = $from_date;
    $dateParams[] = $to_date;
} elseif ($from_date) {
    $dateConditions[] = "DATE(COALESCE(t.checkout_date, t.checked_out_at, t.created_at)) >= ?";
    $dateTypes .= "s";
    $dateParams[] = $from_date;
} elseif ($to_date) {
    $dateConditions[] = "DATE(COALESCE(t.checkout_date, t.checked_out_at, t.created_at)) <= ?";
    $dateTypes .= "s";
    $dateParams[] = $to_date;
}

$baseSelect = "SELECT t.*, 
                      p.assigned_date_time AS p_assigned_dt,
                      p.start_date_time AS p_start_dt,
                      COALESCE(p.deadline_date_time, t.deadline_date_time) AS p_deadline_dt,
                      p.end_date_time AS p_end_dt,
                      p.total_duration AS p_total_duration,
                      p.performance_status AS p_perf_status,
                      p.late_by AS p_late_by,
                      p.points_earned AS p_points_earned
               FROM tasks t
               LEFT JOIN sales_rep_performance p ON t.id = p.task_id";

if ($fetchAll) {
    if (!empty($dateConditions)) {
        $where = implode(' AND ', $dateConditions);
        $stmt  = $conn->prepare("$baseSelect WHERE $where ORDER BY t.created_at DESC");
        $stmt->bind_param($dateTypes, ...$dateParams);
        $stmt->execute();
        $result = $stmt->get_result();
    } else {
        $sql    = "$baseSelect ORDER BY t.created_at DESC";
        $result = $conn->query($sql);
    }
} else {
    $userConditions = [];
    $types          = '';
    $params         = [];

    if ($user_id > 0) {
        $userConditions[] = 't.user_id = ?';
        $types .= 'i';
        $params[] = $user_id;
    }
    if ($sales_rep_name !== '') {
        $userConditions[] = 't.sales_rep_name LIKE ?';
        $types .= 's';
        $params[] = '%' . $sales_rep_name . '%';
    }

    if (!empty($userConditions)) {
        $where = '(' . implode(' OR ', $userConditions) . ')';
        if (!empty($dateConditions)) {
            $where .= ' AND ' . implode(' AND ', $dateConditions);
            $types .= $dateTypes;
            $params = array_merge($params, $dateParams);
        }
        $stmt  = $conn->prepare("$baseSelect WHERE $where ORDER BY t.created_at DESC");
        if ($types) {
            $stmt->bind_param($types, ...$params);
        }
        $stmt->execute();
        $result = $stmt->get_result();
    } else {
        $result = $conn->query("SELECT * FROM tasks WHERE 1=0");
    }
}

$isAdmin = ($fetchAll || (isset($_GET['role']) && strtolower($_GET['role']) === 'admin') || (isset($_GET['is_admin']) && $_GET['is_admin'] == '1'));

$tasks = [];
while ($row = $result->fetch_assoc()) {
    $evaluated = evaluate_task_performance($row);

    $taskItem = [
        "id"                                  => (int)$row['id'],
        "task_id"                             => (int)$row['id'],
        "user_id"                             => (int)($row['user_id'] ?? 0),
        "sales_rep_name"                      => (string)($row['sales_rep_name'] ?? ''),
        "task_basis"                          => (string)($row['task_basis'] ?? ''),
        "doctor_name"                         => (string)($row['doctor_name'] ?? ''),
        "clinic_name"                         => (string)($row['clinic_name'] ?? ''),
        "task_category"                       => (string)($row['task_category'] ?? ''),
        "source_lat"                          => isset($row['source_lat']) ? (float)$row['source_lat'] : null,
        "source_lng"                          => isset($row['source_lng']) ? (float)$row['source_lng'] : null,
        "source_address"                      => (string)($row['source_address'] ?? ''),
        "clinic_lat"                          => (float)($row['clinic_lat'] ?? 0),
        "clinic_lng"                          => (float)($row['clinic_lng'] ?? 0),
        "clinic_address"                      => (string)($row['clinic_address'] ?? ''),
        "notes"                               => (string)($row['notes'] ?? ''),
        "status"                              => (string)($row['status'] ?? 'pending'),
        "checkout_type"                       => (string)($row['checkout_type'] ?? ''),
        "checkout_date"                       => (string)($row['checkout_date'] ?? ''),
        "checkout_time"                       => (string)($row['checkout_time'] ?? ''),
        "checked_out_at"                      => (string)($row['checked_out_at'] ?? ''),
        "checkout_lat"                        => isset($row['checkout_lat']) ? (float)$row['checkout_lat'] : null,
        "checkout_lng"                        => isset($row['checkout_lng']) ? (float)$row['checkout_lng'] : null,
        "destination_distance_meters"         => isset($row['destination_distance_meters']) ? (float)$row['destination_distance_meters'] : null,
        "final_distance_meters"               => isset($row['final_distance_meters']) ? (float)$row['final_distance_meters'] : (isset($row['destination_distance_meters']) ? (float)$row['destination_distance_meters'] : null),
        "destination_reached_at"              => (string)($row['destination_reached_at'] ?? ''),
        "target_deadline_at"                  => (string)($row['target_deadline_at'] ?? ''),
        "target_duration_seconds"             => (int)($row['target_duration_seconds'] ?? 300),
        "is_inside_destination"               => (bool)($row['is_inside_destination'] ?? false),
        "time_inside_destination_seconds"     => (int)($row['time_inside_destination_seconds'] ?? 0),
        "last_destination_distance_meters"    => isset($row['last_destination_distance_meters']) ? (float)$row['last_destination_distance_meters'] : null,
        "completion_result"                   => (string)($row['completion_result'] ?? ''),
        "overtime_duration_seconds"           => (int)($row['overtime_duration_seconds'] ?? 0),
        "deadline_date_time"                  => (string)($evaluated['deadline_date_time'] ?? ''),
        "assigned_date_time"                  => (string)($evaluated['assigned_date_time'] ?? ''),
        "start_date_time"                     => (string)($evaluated['start_date_time'] ?? ''),
        "end_date_time"                       => (string)($evaluated['end_date_time'] ?? ''),
        "total_duration"                      => (string)($evaluated['total_duration'] ?? '—'),
        "performance_status"                  => (string)$evaluated['performance_status'],
        "color_category"                      => (string)$evaluated['color_category'],
        "late_by"                             => (string)($evaluated['late_by'] ?? ''),
        "points_earned"                       => (int)$evaluated['points_earned'],
        "created_at"                          => (string)($row['created_at'] ?? ''),
        "updated_at"                          => (string)($row['updated_at'] ?? ''),
    ];

    // Privacy rule: Overtime Reason is visible to Admin ONLY
    if ($isAdmin) {
        $taskItem["overtime_reason"] = (string)($row['overtime_reason'] ?? '');
    }

    $tasks[] = $taskItem;
}

$summary = calculate_sales_rep_summary($tasks);

echo json_encode([
    "success"  => true,
    "count"    => count($tasks),
    "user_id"  => $user_id,
    "rep_name" => $sales_rep_name,
    "summary"  => $summary,
    "tasks"    => $tasks,
]);

$conn->close();
?>
