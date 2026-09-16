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
$status_filter  = isset($_GET['filter']) ? strtolower(trim($_GET['filter'])) : (isset($_GET['status_filter']) ? strtolower(trim($_GET['status_filter'])) : 'overall');
$from_date_raw  = isset($_GET['from_date']) ? trim($_GET['from_date']) : '';
$to_date_raw    = isset($_GET['to_date']) ? trim($_GET['to_date']) : '';

function parse_ymd_filter($d) {
    if (empty($d)) return null;
    $d = str_replace('/', '-', $d);
    $ts = strtotime($d);
    return ($ts !== false) ? date('Y-m-d', $ts) : null;
}

$from_date = parse_ymd_filter($from_date_raw);
$to_date   = parse_ymd_filter($to_date_raw);

// Fetch all sales reps first
$repQuery = "SELECT id, name, email, phone FROM users WHERE role = 'sales_rep' ORDER BY id ASC";
$repRes = $conn->query($repQuery);
$allRepsMap = [];
if ($repRes && $repRes->num_rows > 0) {
    while ($r = $repRes->fetch_assoc()) {
        $allRepsMap[(int)$r['id']] = [
            'id'    => (int)$r['id'],
            'name'  => trim($r['name']),
            'email' => trim($r['email']),
            'phone' => trim($r['phone']),
            'tasks' => []
        ];
    }
}

// Fetch tasks
$sql = "SELECT t.*, 
               COALESCE(p.assigned_date_time, t.assigned_at, t.created_at) AS p_assigned_dt,
               COALESCE(p.start_date_time, t.started_at) AS p_start_dt,
               COALESCE(p.deadline_date_time, t.deadline_date_time) AS p_deadline_dt,
               COALESCE(p.end_date_time, t.checked_out_at) AS p_end_dt,
               p.total_duration AS p_total_duration,
               p.performance_status AS p_perf_status,
               p.late_by AS p_late_by,
               p.points_earned AS p_points_earned
        FROM tasks t
        LEFT JOIN sales_rep_performance p ON t.id = p.task_id
        ORDER BY t.created_at DESC";

$result = $conn->query($sql);
$allEvaluatedTasks = [];

if ($result && $result->num_rows > 0) {
    while ($row = $result->fetch_assoc()) {
        $evaluated = evaluate_task_performance($row);

        // Combine task table metadata with evaluated performance
        $item = [
            'task_id'            => (int)$row['id'],
            'id'                 => (int)$row['id'],
            'user_id'            => (int)($row['user_id'] ?? 0),
            'sales_rep_id'       => (int)($row['user_id'] ?? 0),
            'sales_rep_name'     => (string)($row['sales_rep_name'] ?? ''),
            'doctor_name'        => (string)($row['doctor_name'] ?? ''),
            'clinic_name'        => (string)($row['clinic_name'] ?? ''),
            'clinic_address'     => (string)($row['clinic_address'] ?? ''),
            'task_category'      => (string)($row['task_category'] ?? ''),
            'task_basis'         => (string)($row['task_basis'] ?? ''),
            'notes'              => (string)($row['notes'] ?? ''),
            'status'             => (string)($row['status'] ?? 'pending'),
            'task_status'        => (string)$evaluated['task_status'],
            'assigned_date_time' => (string)($evaluated['assigned_date_time'] ?? ''),
            'start_date_time'    => (string)($evaluated['start_date_time'] ?? ''),
            'deadline_date_time' => (string)($evaluated['deadline_date_time'] ?? ''),
            'end_date_time'      => (string)($evaluated['end_date_time'] ?? ''),
            'total_duration'     => (string)($evaluated['total_duration'] ?? '—'),
            'performance_status' => (string)$evaluated['performance_status'],
            'color_category'     => (string)$evaluated['color_category'], // 'GREEN' or 'RED'
            'late_by'            => (string)($evaluated['late_by'] ?? ''),
            'points_earned'      => (int)$evaluated['points_earned'],
            'checkout_type'      => (string)($row['checkout_type'] ?? ''),
            'created_at'         => (string)($row['created_at'] ?? ''),
        ];

        $allEvaluatedTasks[] = $item;

        // Group into rep map
        $repId = (int)$row['user_id'];
        $repName = strtolower(trim($row['sales_rep_name'] ?? ''));

        $foundKey = null;
        if ($repId > 0 && isset($allRepsMap[$repId])) {
            $foundKey = $repId;
        } else {
            foreach ($allRepsMap as $k => $rData) {
                if (strtolower($rData['name']) === $repName) {
                    $foundKey = $k;
                    break;
                }
            }
        }

        if ($foundKey !== null) {
            $allRepsMap[$foundKey]['tasks'][] = $item;
        }
    }
}

// Calculate per-rep summaries
$repSummaries = [];
foreach ($allRepsMap as $rId => $rData) {
    $summary = calculate_sales_rep_summary($rData['tasks']);
    $repSummaries[] = [
        'id'                 => $rData['id'],
        'name'               => $rData['name'],
        'email'              => $rData['email'],
        'phone'              => $rData['phone'],
        'total_tasks'        => $summary['total_tasks'],
        'completed_tasks'    => $summary['completed_tasks'],
        'pending_tasks'      => $summary['pending_tasks'],
        'green_tasks'        => $summary['green_tasks'],
        'red_tasks'          => $summary['red_tasks'],
        'overdue_tasks'      => $summary['overdue_tasks'],
        'on_track_tasks'     => $summary['on_track_tasks'],
        'on_time_percentage' => $summary['on_time_percentage'],
        'performance_score'  => $summary['performance_score'],
        'score_display'      => $summary['score_display'],
        'has_data'           => $summary['has_data'],
    ];
}

// Apply Filters to Tasks list
$filteredTasks = $allEvaluatedTasks;

// 1. Rep filter
if ($user_id > 0) {
    $filteredTasks = array_values(array_filter($filteredTasks, function($t) use ($user_id) {
        return (int)$t['user_id'] === $user_id;
    }));
} elseif ($sales_rep_name !== '' && strtolower($sales_rep_name) !== 'all' && strtolower($sales_rep_name) !== 'all sales reps') {
    $targetName = strtolower($sales_rep_name);
    $filteredTasks = array_values(array_filter($filteredTasks, function($t) use ($targetName) {
        return strtolower(trim($t['sales_rep_name'])) === $targetName;
    }));
}

// 2. Date range filter
if ($from_date || $to_date) {
    $filteredTasks = array_values(array_filter($filteredTasks, function($t) use ($from_date, $to_date) {
        $raw = !empty($t['end_date_time']) ? $t['end_date_time'] : $t['created_at'];
        if (strlen($raw) < 10) return false;
        $d = substr($raw, 0, 10);
        if ($from_date && $to_date) {
            return ($d >= $from_date && $d <= $to_date);
        } elseif ($from_date) {
            return ($d >= $from_date);
        } elseif ($to_date) {
            return ($d <= $to_date);
        }
        return true;
    }));
}

// 3. Status filter (Overall, Green, Red)
if ($status_filter === 'green') {
    $filteredTasks = array_values(array_filter($filteredTasks, function($t) {
        return $t['color_category'] === 'GREEN' && $t['performance_status'] === 'GREAT / ON TIME';
    }));
} elseif ($status_filter === 'red') {
    $filteredTasks = array_values(array_filter($filteredTasks, function($t) {
        return $t['color_category'] === 'RED' || $t['performance_status'] === 'BAD / LATE' || $t['performance_status'] === 'OVERDUE';
    }));
}

// Compute Overall Summary for the selected filter scope
$overallSummary = calculate_sales_rep_summary($filteredTasks);

echo json_encode([
    'success'         => true,
    'count'           => count($filteredTasks),
    'filter'          => $status_filter,
    'user_id'         => $user_id,
    'sales_rep_name'  => $sales_rep_name,
    'from_date'       => $from_date,
    'to_date'         => $to_date,
    'summary'         => $overallSummary,
    'reps'            => $repSummaries,
    'tasks'           => $filteredTasks,
]);

$conn->close();
?>
