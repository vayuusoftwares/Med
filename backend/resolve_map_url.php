<?php
error_reporting(0);
ini_set('display_errors', 0);

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE");
header("Access-Control-Allow-Headers: *");
header('Content-Type: application/json; charset=UTF-8');

if (\['REQUEST_METHOD'] === 'OPTIONS') { exit(0); }

\ = json_decode(file_get_contents("php://input"), true);
\ = trim(\['url'] ?? (\['url'] ?? (\['url'] ?? '')));

if (empty(\)) {
    echo json_encode(["success" => false, "message" => "URL required."]);
    exit;
}

// 1. Regex checks on initial URL
if (preg_match('/@(-?\d+\.\d+),(-?\d+\.\d+)/', \, \)) {
    echo json_encode(["success" => true, "lat" => (float)\[1], "lng" => (float)\[2]]);
    exit;
}
if (preg_match('/[?&]q=(-?\d+\.\d+),(-?\d+\.\d+)/', \, \)) {
    echo json_encode(["success" => true, "lat" => (float)\[1], "lng" => (float)\[2]]);
    exit;
}
if (preg_match('/[?&]ll=(-?\d+\.\d+),(-?\d+\.\d+)/', \, \)) {
    echo json_encode(["success" => true, "lat" => (float)\[1], "lng" => (float)\[2]]);
    exit;
}
if (preg_match('/[?&]query=(-?\d+\.\d+),(-?\d+\.\d+)/', \, \)) {
    echo json_encode(["success" => true, "lat" => (float)\[1], "lng" => (float)\[2]]);
    exit;
}
if (preg_match('/!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/', \, \)) {
    echo json_encode(["success" => true, "lat" => (float)\[1], "lng" => (float)\[2]]);
    exit;
}
if (preg_match('/(-?\d+\.\d+),\s*(-?\d+\.\d+)/', \, \)) {
    echo json_encode(["success" => true, "lat" => (float)\[1], "lng" => (float)\[2]]);
    exit;
}

// 2. Follow redirects with cURL if shortlink or maps link
if (function_exists('curl_init')) {
    \ = curl_init(\);
    curl_setopt(\, CURLOPT_RETURNTRANSFER, true);
    curl_setopt(\, CURLOPT_HEADER, true);
    curl_setopt(\, CURLOPT_NOBODY, true);
    curl_setopt(\, CURLOPT_FOLLOWLOCATION, true);
    curl_setopt(\, CURLOPT_MAXREDIRS, 5);
    curl_setopt(\, CURLOPT_TIMEOUT, 6);
    curl_setopt(\, CURLOPT_USERAGENT, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)');
    curl_exec(\);
    \ = curl_getinfo(\, CURLINFO_EFFECTIVE_URL);
    curl_close(\);

    if (!empty(\) && \ !== \) {
        if (preg_match('/@(-?\d+\.\d+),(-?\d+\.\d+)/', \, \)) {
            echo json_encode(["success" => true, "lat" => (float)\[1], "lng" => (float)\[2]]);
            exit;
        }
        if (preg_match('/[?&]q=(-?\d+\.\d+),(-?\d+\.\d+)/', \, \)) {
            echo json_encode(["success" => true, "lat" => (float)\[1], "lng" => (float)\[2]]);
            exit;
        }
        if (preg_match('/!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)/', \, \)) {
            echo json_encode(["success" => true, "lat" => (float)\[1], "lng" => (float)\[2]]);
            exit;
        }
    }
}

echo json_encode(["success" => false, "message" => "Coordinates not found in URL."]);
?>
