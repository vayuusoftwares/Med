<?php
// ─────────────────────────────────────────────────────────────────────────────
// performance_engine.php — Centralized Performance & Scoring Engine
// Single Source of Truth for Performance, Points, Deadlines, and History.
// ─────────────────────────────────────────────────────────────────────────────

date_default_timezone_set('Asia/Kolkata');

/**
 * Ensure `sales_rep_performance` table and supporting columns exist.
 */
function ensure_performance_schema($conn) {
    if (!$conn) return;

    // 1. Ensure tasks table has deadline, start, timing, and destination tracking columns
    $taskCols = [
        'start_date_time'                     => "DATETIME NULL",
        'end_date_time'                       => "DATETIME NULL",
        'started_at'                          => "DATETIME NULL",
        'assigned_at'                         => "DATETIME NULL DEFAULT CURRENT_TIMESTAMP",
        'deadline_date_time'                  => "DATETIME NULL",
        'target_deadline_at'                  => "DATETIME NULL",
        'target_duration_seconds'             => "INT NOT NULL DEFAULT 300",
        'destination_reached_at'              => "DATETIME NULL",
        'is_inside_destination'               => "TINYINT(1) NOT NULL DEFAULT 0",
        'time_inside_destination_seconds'     => "INT NOT NULL DEFAULT 0",
        'last_destination_distance_meters'    => "DOUBLE NULL",
        'destination_reached_lat'             => "DOUBLE NULL",
        'destination_reached_lng'             => "DOUBLE NULL",
        'destination_reached_distance_meters' => "DOUBLE NULL",
        'final_distance_meters'               => "DOUBLE NULL",
        'final_lat'                           => "DOUBLE NULL",
        'final_lng'                           => "DOUBLE NULL",
        'completion_result'                 => "VARCHAR(50) NULL DEFAULT 'within_target'",
        'overtime_duration_seconds'           => "INT NOT NULL DEFAULT 0",
        'overtime_reason'                     => "TEXT NULL",
        'overtime_started_at'                 => "DATETIME NULL"
    ];
    foreach ($taskCols as $col => $def) {
        $r = $conn->query("SHOW COLUMNS FROM tasks LIKE '$col'");
        if ($r && $r->num_rows == 0) {
            $conn->query("ALTER TABLE tasks ADD COLUMN $col $def");
        }
    }

    // 2. Ensure clinic_location_tracking table exists (stores 1-min live GPS for each clinic visit)
    $conn->query("CREATE TABLE IF NOT EXISTS clinic_location_tracking (
        id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        task_id INT UNSIGNED NOT NULL,
        user_id INT UNSIGNED NOT NULL,
        sales_rep_name VARCHAR(100) NOT NULL,
        doctor_name VARCHAR(255) NULL DEFAULT '',
        clinic_name VARCHAR(255) NULL DEFAULT '',
        clinic_address TEXT NULL,
        type VARCHAR(50) NOT NULL DEFAULT 'task_tracking',
        lat DECIMAL(10, 8) NOT NULL,
        lng DECIMAL(11, 8) NOT NULL,
        notes TEXT NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_task_id (task_id),
        INDEX idx_user_id (user_id),
        INDEX idx_created_at (created_at)
    )");

    // Ensure attendance_history table exists for check_in / check_out
    $conn->query("CREATE TABLE IF NOT EXISTS attendance_history (
        id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        user_id INT UNSIGNED NOT NULL,
        sales_rep_name VARCHAR(100) NOT NULL,
        type VARCHAR(50) NOT NULL DEFAULT 'check_in',
        lat DOUBLE NOT NULL,
        lng DOUBLE NOT NULL,
        address VARCHAR(255) NULL,
        notes TEXT NULL,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_user_id (user_id),
        INDEX idx_created_at (created_at)
    )");

    // 3. Ensure sales_rep_performance table exists
    $createTableSql = "CREATE TABLE IF NOT EXISTS sales_rep_performance (
        id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        sales_rep_id INT UNSIGNED NOT NULL,
        task_id INT UNSIGNED NOT NULL UNIQUE,
        assigned_date_time DATETIME NULL,
        start_date_time DATETIME NULL,
        deadline_date_time DATETIME NULL,
        end_date_time DATETIME NULL,
        total_duration VARCHAR(100) NULL,
        task_status VARCHAR(50) NOT NULL DEFAULT 'pending',
        performance_status VARCHAR(50) NOT NULL DEFAULT 'PENDING / ON TRACK',
        late_by VARCHAR(100) NULL,
        points_earned INT NOT NULL DEFAULT 0,
        created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_sales_rep_id (sales_rep_id),
        INDEX idx_performance_status (performance_status),
        INDEX idx_deadline (deadline_date_time)
    )";
    $conn->query($createTableSql);
}

/**
 * Human-readable duration formatter
 */
function format_duration_seconds($seconds) {
    if ($seconds === null || $seconds < 0) return null;
    if ($seconds < 60) return $seconds . " sec";
    
    $minutes = floor($seconds / 60);
    if ($minutes < 60) return $minutes . " min";
    
    $hours = floor($minutes / 60);
    $remMinutes = $minutes % 60;
    if ($hours < 24) {
        return $remMinutes > 0 ? "{$hours} hr {$remMinutes} min" : "{$hours} hr";
    }
    
    $days = floor($hours / 24);
    $remHours = $hours % 24;
    return $remHours > 0 ? "{$days} days {$remHours} hrs" : "{$days} days";
}

/**
 * Human-readable late-by formatter
 */
function format_late_by_seconds($seconds) {
    if ($seconds === null || $seconds <= 0) return null;
    
    $minutes = floor($seconds / 60);
    if ($minutes < 60) return ($minutes > 0 ? $minutes : 1) . " min";
    
    $hours = floor($minutes / 60);
    $remMinutes = $minutes % 60;
    if ($hours < 24) {
        return $remMinutes > 0 ? "{$hours} hr {$remMinutes} min" : "{$hours} hr";
    }
    
    $days = floor($hours / 24);
    $remHours = $hours % 24;
    $remMin = $minutes % 60;
    if ($days < 3) {
        return "{$days} days {$remHours} hrs {$remMin} min";
    }
    return "{$days} days {$remHours} hrs";
}

/**
 * Parse an arbitrary date string safely into Y-m-d H:i:s or DateTime object in Asia/Kolkata
 */
function parse_kolkata_datetime($dtStr) {
    if (empty($dtStr)) return null;
    $trimmed = trim($dtStr);
    if ($trimmed === '' || $trimmed === '0000-00-00 00:00:00' || $trimmed === '0000-00-00') return null;
    
    try {
        $tz = new DateTimeZone('Asia/Kolkata');
        $dt = new DateTime($trimmed, $tz);
        return $dt;
    } catch (Exception $e) {
        return null;
    }
}

/**
 * Format DateTime object or string into standard SQL 'Y-m-d H:i:s' in Asia/Kolkata
 */
function format_kolkata_sql_datetime($dt) {
    if ($dt === null) return null;
    if (is_string($dt)) {
        $parsed = parse_kolkata_datetime($dt);
        return $parsed ? $parsed->format('Y-m-d H:i:s') : null;
    }
    if ($dt instanceof DateTime) {
        return $dt->format('Y-m-d H:i:s');
    }
    return null;
}

/**
 * CENTRALIZED PERFORMANCE CALCULATION
 * Evaluates a single task record using exact Date+Time in Asia/Kolkata.
 */
function evaluate_task_performance($task) {
    $tz = new DateTimeZone('Asia/Kolkata');
    $now = new DateTime('now', $tz);

    $taskId = (int)($task['id'] ?? $task['task_id'] ?? 0);
    $repId  = (int)($task['user_id'] ?? $task['sales_rep_id'] ?? 0);
    $status = strtolower(trim($task['status'] ?? $task['task_status'] ?? 'pending'));

    // Resolve assigned time
    $assignedStr = $task['assigned_date_time'] ?? $task['assigned_at'] ?? $task['created_at'] ?? null;
    $assignedDt = parse_kolkata_datetime($assignedStr);

    // Resolve started time (only if explicitly started)
    $startedStr = $task['start_date_time'] ?? $task['started_at'] ?? null;
    $startedDt = parse_kolkata_datetime($startedStr);

    // Resolve deadline time
    $deadlineStr = $task['deadline_date_time'] ?? $task['deadline_at'] ?? $task['deadline'] ?? null;
    $deadlineDt = parse_kolkata_datetime($deadlineStr);

    // Resolve completed time
    $completedStr = $task['end_date_time'] ?? $task['checked_out_at'] ?? $task['checkout_datetime'] ?? null;
    if (!$completedStr && !empty($task['checkout_date'])) {
        $timePart = !empty($task['checkout_time']) ? trim($task['checkout_time']) : '00:00:00';
        $completedStr = trim($task['checkout_date']) . ' ' . $timePart;
    }
    $completedDt = parse_kolkata_datetime($completedStr);

    $isCompleted  = ($status === 'completed');
    $isInProgress = ($status === 'in_progress' || $status === 'started');
    $performanceStatus = 'PENDING / ON TRACK';
    $lateBy = null;
    $totalDuration = null;
    $pointsEarned = 0;
    $colorCategory = 'GREEN'; // GREEN, RED, NEUTRAL

    // Calculate total duration if completed or started
    if ($isCompleted && $completedDt) {
        $durationStart = $startedDt ?: $assignedDt;
        if ($durationStart) {
            $durationSeconds = $completedDt->getTimestamp() - $durationStart->getTimestamp();
            if ($durationSeconds >= 0) {
                $totalDuration = format_duration_seconds($durationSeconds);
            }
        }
    } elseif ($isInProgress && $startedDt) {
        $durationSeconds = $now->getTimestamp() - $startedDt->getTimestamp();
        if ($durationSeconds >= 0) {
            $totalDuration = format_duration_seconds($durationSeconds);
        }
    }

    if ($deadlineDt) {
        if ($isCompleted) {
            $comp = $completedDt ?: $now;
            if ($comp <= $deadlineDt) {
                // Completed <= Deadline => GREEN / GREAT / ON TIME
                $performanceStatus = 'GREAT / ON TIME';
                $colorCategory = 'GREEN';
                $lateBy = null;
                $pointsEarned = 10;
            } else {
                // Completed > Deadline => RED / BAD / LATE
                $performanceStatus = 'BAD / LATE';
                $colorCategory = 'RED';
                $diffSec = $comp->getTimestamp() - $deadlineDt->getTimestamp();
                $lateBy = format_late_by_seconds($diffSec);
                $pointsEarned = -5;
            }
        } elseif ($isInProgress) {
            if ($now > $deadlineDt) {
                $performanceStatus = 'OVERDUE';
                $colorCategory = 'RED';
                $diffSec = $now->getTimestamp() - $deadlineDt->getTimestamp();
                $lateBy = format_late_by_seconds($diffSec);
                $pointsEarned = 0;
            } else {
                $performanceStatus = 'IN PROGRESS / ON TRACK';
                $colorCategory = 'GREEN';
                $lateBy = null;
                $pointsEarned = 0;
            }
        } else {
            // Pending (not yet started)
            if ($now > $deadlineDt) {
                $performanceStatus = 'OVERDUE';
                $colorCategory = 'RED';
                $diffSec = $now->getTimestamp() - $deadlineDt->getTimestamp();
                $lateBy = format_late_by_seconds($diffSec);
                $pointsEarned = 0;
            } else {
                $performanceStatus = 'PENDING / ON TRACK';
                $colorCategory = 'GREEN';
                $lateBy = null;
                $pointsEarned = 0;
            }
        }
    } else {
        // No explicit deadline set on task -> treat based on status
        if ($isCompleted) {
            $performanceStatus = 'GREAT / ON TIME';
            $colorCategory = 'GREEN';
            $pointsEarned = 10;
        } elseif ($isInProgress) {
            $performanceStatus = 'IN PROGRESS / ON TRACK';
            $colorCategory = 'GREEN';
            $pointsEarned = 0;
        } else {
            $performanceStatus = 'PENDING / ON TRACK';
            $colorCategory = 'GREEN';
            $pointsEarned = 0;
        }
    }

    $normalizedTaskStatus = $isCompleted ? 'completed' : ($isInProgress ? 'in_progress' : ($status === 'cancelled' ? 'cancelled' : 'pending'));

    return [
        'task_id'            => $taskId,
        'sales_rep_id'       => $repId,
        'assigned_date_time' => format_kolkata_sql_datetime($assignedDt),
        'start_date_time'    => format_kolkata_sql_datetime($startedDt),
        'deadline_date_time' => format_kolkata_sql_datetime($deadlineDt),
        'end_date_time'      => format_kolkata_sql_datetime($completedDt),
        'total_duration'     => $totalDuration,
        'task_status'        => $normalizedTaskStatus,
        'performance_status' => $performanceStatus,
        'color_category'     => $colorCategory,
        'late_by'            => $lateBy,
        'points_earned'      => $pointsEarned,
    ];
}

/**
 * Calculate Performance Metrics & Score out of 100 for a list of evaluated tasks.
 * Single Source of Truth for Points and Performance Score.
 */
function calculate_sales_rep_summary($evaluatedTasks) {
    $totalTasks = count($evaluatedTasks);
    $completedTasks = 0;
    $greenTasks = 0;
    $redTasks = 0;
    $overdueTasks = 0;
    $onTrackTasks = 0;
    $pendingTasks = 0;

    foreach ($evaluatedTasks as $t) {
        $st = $t['performance_status'] ?? '';
        $tStatus = $t['task_status'] ?? '';

        if ($tStatus === 'completed') {
            $completedTasks++;
        }

        if ($st === 'GREAT / ON TIME' || $st === 'GREAT' || $st === 'ON TIME') {
            $greenTasks++;
        } elseif ($st === 'BAD / LATE' || $st === 'BAD' || $st === 'LATE') {
            $redTasks++;
        } elseif ($st === 'OVERDUE') {
            $overdueTasks++;
        } elseif ($st === 'ON TRACK') {
            $onTrackTasks++;
        } else {
            $pendingTasks++;
        }
    }

    // Evaluated tasks are tasks that have concluded (completed on-time + completed late + overdue pending)
    $evaluatedCount = $greenTasks + $redTasks + $overdueTasks;

    if ($completedTasks === 0 && $overdueTasks === 0) {
        // No evaluated performance data
        $performanceScore = 0;
        $onTimePercentage = 0.0;
        $hasData = false;
        $scoreDisplay = "0 / 100";
    } else {
        $hasData = true;
        // On-Time Percentage = (Green / Evaluated) * 100
        $onTimePercentage = $evaluatedCount > 0 ? round(($greenTasks / $evaluatedCount) * 100.0, 1) : 0.0;
        $performanceScore = (int)round($onTimePercentage);
        if ($performanceScore > 100) $performanceScore = 100;
        if ($performanceScore < 0) $performanceScore = 0;
        $scoreDisplay = "{$performanceScore} / 100";
    }

    return [
        'total_tasks'        => $totalTasks,
        'completed_tasks'    => $completedTasks,
        'pending_tasks'      => $totalTasks - $completedTasks,
        'green_tasks'        => $greenTasks,
        'red_tasks'          => $redTasks,
        'overdue_tasks'      => $overdueTasks,
        'on_track_tasks'     => $onTrackTasks,
        'on_time_percentage' => $onTimePercentage,
        'performance_score'  => $performanceScore,
        'has_data'           => $hasData,
        'score_display'      => $scoreDisplay,
    ];
}

/**
 * Syncs a single task's performance record into `sales_rep_performance` table.
 * Exactly one record per task (unique key task_id).
 */
function sync_task_performance_record($conn, $task) {
    if (!$conn) return null;
    ensure_performance_schema($conn);

    $perf = evaluate_task_performance($task);
    $taskId = (int)$perf['task_id'];
    $repId  = (int)$perf['sales_rep_id'];

    if ($taskId <= 0) return null;

    $stmt = $conn->prepare("INSERT INTO sales_rep_performance 
        (sales_rep_id, task_id, assigned_date_time, start_date_time, deadline_date_time, end_date_time, total_duration, task_status, performance_status, late_by, points_earned)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
        sales_rep_id = VALUES(sales_rep_id),
        assigned_date_time = VALUES(assigned_date_time),
        start_date_time = VALUES(start_date_time),
        deadline_date_time = VALUES(deadline_date_time),
        end_date_time = VALUES(end_date_time),
        total_duration = VALUES(total_duration),
        task_status = VALUES(task_status),
        performance_status = VALUES(performance_status),
        late_by = VALUES(late_by),
        points_earned = VALUES(points_earned),
        updated_at = NOW()");

    if ($stmt) {
        $stmt->bind_param(
            "iissssssssi",
            $repId,
            $taskId,
            $perf['assigned_date_time'],
            $perf['start_date_time'],
            $perf['deadline_date_time'],
            $perf['end_date_time'],
            $perf['total_duration'],
            $perf['task_status'],
            $perf['performance_status'],
            $perf['late_by'],
            $perf['points_earned']
        );
        $stmt->execute();
        $stmt->close();
    }

    return $perf;
}

/**
 * Synchronize all existing tasks from `tasks` table into `sales_rep_performance`.
 * Only syncs real database tasks without creating any dummy records.
 */
function sync_all_existing_tasks_performance($conn) {
    if (!$conn) return;
    ensure_performance_schema($conn);

    $sql = "SELECT t.*, u.id as user_id_from_user FROM tasks t 
            LEFT JOIN users u ON (t.user_id = u.id OR LOWER(t.sales_rep_name) = LOWER(u.name))
            ORDER BY t.id ASC";
    $result = $conn->query($sql);
    if ($result && $result->num_rows > 0) {
        while ($row = $result->fetch_assoc()) {
            if (empty($row['user_id']) && !empty($row['user_id_from_user'])) {
                $row['user_id'] = (int)$row['user_id_from_user'];
            }
            sync_task_performance_record($conn, $row);
        }
    }
}
?>
