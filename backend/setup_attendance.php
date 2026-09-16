<?php
/**
 * setup_attendance.php
 * Creates the attendance_history table if it doesn't exist.
 * Run once via browser: http://192.168.29.244/backend/setup_attendance.php
 */
header('Content-Type: text/plain');

$conn = new mysqli("localhost", "root", "", "medsafe_db");
if ($conn->connect_error) {
    die("DB connection failed: " . $conn->connect_error);
}

// Create attendance_history table
$sql = "CREATE TABLE IF NOT EXISTS attendance_history (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id       INT UNSIGNED NOT NULL,
    sales_rep_name VARCHAR(120) NOT NULL,
    type          ENUM('check_in','check_out') NOT NULL,
    lat           DOUBLE NOT NULL,
    lng           DOUBLE NOT NULL,
    address       VARCHAR(500) NULL DEFAULT '',
    notes         TEXT NULL,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user   (user_id),
    INDEX idx_type   (type),
    INDEX idx_date   (created_at)
)";

if ($conn->query($sql)) {
    echo "OK: attendance_history table created/verified.\n";
} else {
    echo "ERROR creating table: " . $conn->error . "\n";
}

// Show current count
$r = $conn->query("SELECT COUNT(*) as cnt FROM attendance_history");
$row = $r->fetch_assoc();
echo "Current rows in attendance_history: " . $row['cnt'] . "\n";

$conn->close();
echo "Done.\n";
?>
