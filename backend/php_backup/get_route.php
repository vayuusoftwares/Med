<?php
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE");
header("Access-Control-Allow-Headers: *");
header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { exit(0); }

$src_lat  = (float)($_GET['src_lat'] ?? 0);
$src_lng  = (float)($_GET['src_lng'] ?? 0);
$dest_lat = (float)($_GET['dest_lat'] ?? 0);
$dest_lng = (float)($_GET['dest_lng'] ?? 0);

if (!$src_lat || !$src_lng || !$dest_lat || !$dest_lng) {
    echo json_encode(["success" => false, "message" => "Coordinates required."]);
    exit;
}

$urls = [
    "https://router.project-osrm.org/route/v1/driving/{$src_lng},{$src_lat};{$dest_lng},{$dest_lat}?overview=full&geometries=polyline",
    "https://routing.openstreetmap.de/routed-car/route/v1/driving/{$src_lng},{$src_lat};{$dest_lng},{$dest_lat}?overview=full&geometries=polyline",
    "https://router.project-osrm.org/route/v1/driving/{$src_lng},{$src_lat};{$dest_lng},{$dest_lat}?overview=full&geometries=geojson",
    "https://routing.openstreetmap.de/routed-car/route/v1/driving/{$src_lng},{$src_lat};{$dest_lng},{$dest_lat}?overview=full&geometries=geojson"
];

$opts = [
    "http" => [
        "method" => "GET",
        "header" => "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)\r\nAccept: application/json\r\n",
        "timeout" => 8
    ],
    "ssl" => [
        "verify_peer" => false,
        "verify_peer_name" => false
    ]
];
$context = stream_context_create($opts);

function decodePolylinePHP($encoded) {
    $length = strlen($encoded);
    $index = 0;
    $points = [];
    $lat = 0;
    $lng = 0;
    while ($index < $length) {
        $b = 0; $shift = 0; $result = 0;
        do {
            $b = ord($encoded[$index++]) - 63;
            $result |= ($b & 0x1f) << $shift;
            $shift += 5;
        } while ($b >= 0x20);
        $dlat = (($result & 1) ? ~($result >> 1) : ($result >> 1));
        $lat += $dlat;

        $shift = 0; $result = 0;
        do {
            $b = ord($encoded[$index++]) - 63;
            $result |= ($b & 0x1f) << $shift;
            $shift += 5;
        } while ($b >= 0x20);
        $dlng = (($result & 1) ? ~($result >> 1) : ($result >> 1));
        $lng += $dlng;

        $points[] = [$lng / 1e5, $lat / 1e5];
    }
    return $points;
}

foreach ($urls as $osrm_url) {
    $response = @file_get_contents($osrm_url, false, $context);
    if ($response !== false) {
        $data = json_decode($response, true);
        if (isset($data['code']) && $data['code'] === 'Ok' && !empty($data['routes'][0])) {
            $route = $data['routes'][0];
            $distance = $route['distance'] ?? 0;
            
            if (is_string($route['geometry'])) {
                $points = decodePolylinePHP($route['geometry']);
            } else if (isset($route['geometry']['coordinates'])) {
                $points = $route['geometry']['coordinates'];
            } else {
                continue;
            }

            if (!empty($points)) {
                echo json_encode([
                    "success" => true,
                    "is_road_route" => true,
                    "points" => $points,
                    "distance" => $distance
                ]);
                exit;
            }
        }
    }
}

echo json_encode(["success" => false, "message" => "Could not resolve road route."]);
?>
