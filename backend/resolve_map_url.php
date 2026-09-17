<?php
error_reporting(0);
ini_set('display_errors', 0);

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS, PUT, DELETE");
header("Access-Control-Allow-Headers: *");
header('Content-Type: application/json; charset=UTF-8');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { exit(0); }

$input = json_decode(file_get_contents("php://input"), true);
$url = trim($input['url'] ?? ($_GET['url'] ?? ($_POST['url'] ?? '')));

if (empty($url)) {
    echo json_encode(["success" => false, "message" => "URL required."]);
    exit;
}

function is_valid_lat_lng($lat, $lng) {
    return is_numeric($lat) && is_numeric($lng) &&
           $lat >= -90.0 && $lat <= 90.0 &&
           $lng >= -180.0 && $lng <= 180.0 &&
           ($lat != 0.0 || $lng != 0.0);
}

function extract_coords_from_text($text) {
    if (empty($text)) return null;

    // 1. PRIORITY 1: Exact Google Maps Place / Dropped Pin (!3d<lat>!4d<lng> or !4d<lng>!3d<lat>)
    if (preg_match('/!3d(-?\d+\.\d+).*?!4d(-?\d+\.\d+)/s', $text, $matches)) {
        $lat = (float)$matches[1];
        $lng = (float)$matches[2];
        if (is_valid_lat_lng($lat, $lng)) {
            return ["lat" => $lat, "lng" => $lng, "source" => "google_maps_exact_pin"];
        }
    }
    if (preg_match('/!4d(-?\d+\.\d+).*?!3d(-?\d+\.\d+)/s', $text, $matches)) {
        $lat = (float)$matches[2];
        $lng = (float)$matches[1];
        if (is_valid_lat_lng($lat, $lng)) {
            return ["lat" => $lat, "lng" => $lng, "source" => "google_maps_exact_pin"];
        }
    }

    // 2. PRIORITY 2: Explicit Target Location / Destination / Query / Pinned coords
    if (preg_match('/[?&](?:destination|daddr)=(-?\d+\.\d+)[,+](-?\d+\.\d+)/i', $text, $matches)) {
        $lat = (float)$matches[1];
        $lng = (float)$matches[2];
        if (is_valid_lat_lng($lat, $lng)) {
            return ["lat" => $lat, "lng" => $lng, "source" => "google_maps_destination"];
        }
    }
    if (preg_match('/[?&](?:q|query|loc)=(?:loc:)?(-?\d+\.\d+)[,+](-?\d+\.\d+)/i', $text, $matches)) {
        $lat = (float)$matches[1];
        $lng = (float)$matches[2];
        if (is_valid_lat_lng($lat, $lng)) {
            return ["lat" => $lat, "lng" => $lng, "source" => "google_maps_query"];
        }
    }
    if (preg_match('/[?&]ll=(-?\d+\.\d+)[,+](-?\d+\.\d+)/i', $text, $matches)) {
        $lat = (float)$matches[1];
        $lng = (float)$matches[2];
        if (is_valid_lat_lng($lat, $lng)) {
            return ["lat" => $lat, "lng" => $lng, "source" => "google_maps_ll"];
        }
    }

    // 3. PRIORITY 3: geo: URI
    if (preg_match('/geo:(-?\d+\.\d+),(-?\d+\.\d+)/i', $text, $matches)) {
        $lat = (float)$matches[1];
        $lng = (float)$matches[2];
        if (is_valid_lat_lng($lat, $lng)) {
            return ["lat" => $lat, "lng" => $lng, "source" => "geo_uri"];
        }
    }

    // 4. PRIORITY 4: HTML Meta Tags & Markers (Static map markers, Schema.org, APP_INITIALIZATION_STATE)
    if (preg_match('/markers=(?:[^&]*?(?:%7C|\|))?(-?\d+\.\d+)(?:%2C|,)(-?\d+\.\d+)/i', $text, $matches)) {
        $lat = (float)$matches[1];
        $lng = (float)$matches[2];
        if (is_valid_lat_lng($lat, $lng)) {
            return ["lat" => $lat, "lng" => $lng, "source" => "google_maps_marker"];
        }
    }
    if (preg_match('/itemprop="latitude"[^>]*content="(-?\d+\.\d+)"/i', $text, $mLat) &&
        preg_match('/itemprop="longitude"[^>]*content="(-?\d+\.\d+)"/i', $text, $mLng)) {
        $lat = (float)$mLat[1];
        $lng = (float)$mLng[1];
        if (is_valid_lat_lng($lat, $lng)) {
            return ["lat" => $lat, "lng" => $lng, "source" => "html_meta"];
        }
    }
    if (preg_match('/window\.APP_INITIALIZATION_STATE\s*=\s*\[\[\[(-?\d+\.\d+),(-?\d+\.\d+)\]/', $text, $matches)) {
        $lat = (float)$matches[1];
        $lng = (float)$matches[2];
        if (is_valid_lat_lng($lat, $lng)) {
            return ["lat" => $lat, "lng" => $lng, "source" => "app_init_state"];
        }
    }
    if (preg_match('/\[null,null,(-?\d+\.\d{3,}),(-?\d+\.\d{3,})\]/', $text, $matches)) {
        $lat = (float)$matches[1];
        $lng = (float)$matches[2];
        if (is_valid_lat_lng($lat, $lng)) {
            return ["lat" => $lat, "lng" => $lng, "source" => "app_init_array"];
        }
    }

    // 5. PRIORITY 5: Viewport / Camera Coordinates (@lat,lng)
    if (preg_match('/@(-?\d+\.\d+),(-?\d+\.\d+)/', $text, $matches)) {
        $lat = (float)$matches[1];
        $lng = (float)$matches[2];
        if (is_valid_lat_lng($lat, $lng)) {
            return ["lat" => $lat, "lng" => $lng, "source" => "google_maps_viewport"];
        }
    }

    // 6. PRIORITY 6: Plain coordinate text
    if (preg_match('/^\s*\(?\s*(-?\d{1,3}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)\s*\)?\s*$/', $text, $matches)) {
        $lat = (float)$matches[1];
        $lng = (float)$matches[2];
        if (is_valid_lat_lng($lat, $lng)) {
            return ["lat" => $lat, "lng" => $lng, "source" => "plain_coords"];
        }
    }

    return null;
}

// Step 1: Direct extraction on provided URL
$result = extract_coords_from_text($url);
if ($result !== null) {
    echo json_encode(array_merge(["success" => true], $result));
    exit;
}

// Step 2: Follow redirects with cURL if shortlink or maps link
if (function_exists('curl_init')) {
    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
    curl_setopt($ch, CURLOPT_MAXREDIRS, 10);
    curl_setopt($ch, CURLOPT_TIMEOUT, 8);
    curl_setopt($ch, CURLOPT_USERAGENT, 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36');
    $body = curl_exec($ch);
    $effectiveUrl = curl_getinfo($ch, CURLINFO_EFFECTIVE_URL);
    curl_close($ch);

    if (!empty($effectiveUrl)) {
        $resUrl = extract_coords_from_text($effectiveUrl);
        if ($resUrl !== null) {
            echo json_encode(array_merge(["success" => true], $resUrl));
            exit;
        }
    }

    if (!empty($body)) {
        $resBody = extract_coords_from_text($body);
        if ($resBody !== null) {
            echo json_encode(array_merge(["success" => true], $resBody));
            exit;
        }
    }
}

echo json_encode(["success" => false, "message" => "Coordinates not found in URL."]);
?>
