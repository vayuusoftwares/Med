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

function parse_dms($text) {
    if (preg_match('/(\d{1,3})[°\s]+(\d{1,2}(?:\.\d+)?)[\'′\s]*(?:(\d{1,2}(?:\.\d+)?)[\"″\s]*)?([NSns])[,+\s]+(\d{1,3})[°\s]+(\d{1,2}(?:\.\d+)?)[\'′\s]*(?:(\d{1,2}(?:\.\d+)?)[\"″\s]*)?([EWew])/', $text, $m)) {
        $latDeg = (float)$m[1];
        $latMin = (float)$m[2];
        $latSec = !empty($m[3]) ? (float)$m[3] : 0.0;
        $latDir = strtoupper($m[4]);

        $lngDeg = (float)$m[5];
        $lngMin = (float)$m[6];
        $lngSec = !empty($m[7]) ? (float)$m[7] : 0.0;
        $lngDir = strtoupper($m[8]);

        $lat = $latDeg + ($latMin / 60.0) + ($latSec / 3600.0);
        if ($latDir === 'S') $lat = -$lat;

        $lng = $lngDeg + ($lngMin / 60.0) + ($lngSec / 3600.0);
        if ($lngDir === 'W') $lng = -$lng;

        if (is_valid_lat_lng($lat, $lng)) {
            return ["lat" => $lat, "lng" => $lng, "source" => "dms_coords"];
        }
    }
    return null;
}

function extract_coords_from_text($text) {
    if (empty($text)) return null;

    $decoded = urldecode($text);
    $texts = [$text, $decoded];

    foreach ($texts as $t) {
        // 1. PRIORITY 1: Exact Google Maps Place / Dropped Pin (!3d<lat>!4d<lng> or !4d<lng>!3d<lat> or !1d<lng>!2d<lat>)
        if (preg_match('/!3d(-?\d+\.\d+).*?!4d(-?\d+\.\d+)/s', $t, $matches)) {
            $lat = (float)$matches[1];
            $lng = (float)$matches[2];
            if (is_valid_lat_lng($lat, $lng)) {
                return ["lat" => $lat, "lng" => $lng, "source" => "google_maps_exact_pin"];
            }
        }
        if (preg_match('/!4d(-?\d+\.\d+).*?!3d(-?\d+\.\d+)/s', $t, $matches)) {
            $lat = (float)$matches[2];
            $lng = (float)$matches[1];
            if (is_valid_lat_lng($lat, $lng)) {
                return ["lat" => $lat, "lng" => $lng, "source" => "google_maps_exact_pin"];
            }
        }
        if (preg_match('/!1d(-?\d+\.\d+).*?!2d(-?\d+\.\d+)/s', $t, $matches)) {
            $lat = (float)$matches[2];
            $lng = (float)$matches[1];
            if (is_valid_lat_lng($lat, $lng)) {
                return ["lat" => $lat, "lng" => $lng, "source" => "google_maps_route_destination"];
            }
        }

        // 2. PRIORITY 2: Explicit Target Location / Destination / Query / Pinned coords
        if (preg_match('#/maps/(?:place|search|dir(?:/[^/]+)?)/(-?\d+\.\d+)[,+](-?\d+\.\d+)#i', $t, $matches)) {
            $lat = (float)$matches[1];
            $lng = (float)$matches[2];
            if (is_valid_lat_lng($lat, $lng)) {
                return ["lat" => $lat, "lng" => $lng, "source" => "google_maps_path_place"];
            }
        }
        if (preg_match('/[?&](?:destination|daddr)=(-?\d+\.\d+)[,+](-?\d+\.\d+)/i', $t, $matches)) {
            $lat = (float)$matches[1];
            $lng = (float)$matches[2];
            if (is_valid_lat_lng($lat, $lng)) {
                return ["lat" => $lat, "lng" => $lng, "source" => "google_maps_destination"];
            }
        }
        if (preg_match('/[?&](?:q|query|loc|ll|saddr)=(?:loc:)?(-?\d+\.\d+)[,+](-?\d+\.\d+)/i', $t, $matches)) {
            $lat = (float)$matches[1];
            $lng = (float)$matches[2];
            if (is_valid_lat_lng($lat, $lng)) {
                return ["lat" => $lat, "lng" => $lng, "source" => "google_maps_query"];
            }
        }
        if (preg_match('/[?&]lat=(-?\d+\.\d+)&[?&]?(?:lng|lon)=(-?\d+\.\d+)/i', $t, $matches)) {
            $lat = (float)$matches[1];
            $lng = (float)$matches[2];
            if (is_valid_lat_lng($lat, $lng)) {
                return ["lat" => $lat, "lng" => $lng, "source" => "param_coords"];
            }
        }

        // 3. PRIORITY 3: geo: URI
        if (preg_match('/geo:(-?\d+\.\d+),(-?\d+\.\d+)/i', $t, $matches)) {
            $lat = (float)$matches[1];
            $lng = (float)$matches[2];
            if (is_valid_lat_lng($lat, $lng)) {
                return ["lat" => $lat, "lng" => $lng, "source" => "geo_uri"];
            }
        }

        // 4. PRIORITY 4: Degrees Minutes Seconds (DMS)
        $dms = parse_dms($t);
        if ($dms !== null) return $dms;

        // 5. PRIORITY 5: HTML Meta Tags & Markers (Static map markers, Schema.org, JSON-LD, ICBM)
        if (preg_match('/markers=([^&"\']+)/i', $t, $mParam)) {
            if (preg_match_all('/(-?\d+\.\d+)(?:%2C|,)(-?\d+\.\d+)/i', $mParam[1], $allCoords, PREG_SET_ORDER)) {
                $lastMatch = end($allCoords);
                $lat = (float)$lastMatch[1];
                $lng = (float)$lastMatch[2];
                if (is_valid_lat_lng($lat, $lng)) {
                    return ["lat" => $lat, "lng" => $lng, "source" => "google_maps_marker"];
                }
            }
        }
        if (preg_match('/itemprop=["\']latitude["\'][^>]*content=["\'](-?\d+\.\d+)["\']/i', $t, $mLat) &&
            preg_match('/itemprop=["\']longitude["\'][^>]*content=["\'](-?\d+\.\d+)["\']/i', $t, $mLng)) {
            $lat = (float)$mLat[1];
            $lng = (float)$mLng[1];
            if (is_valid_lat_lng($lat, $lng)) {
                return ["lat" => $lat, "lng" => $lng, "source" => "html_meta"];
            }
        }
        if (preg_match('/"latitude"\s*:\s*"?(-?\d+\.\d+)"?/i', $t, $mLat) &&
            preg_match('/"longitude"\s*:\s*"?(-?\d+\.\d+)"?/i', $t, $mLng)) {
            $lat = (float)$mLat[1];
            $lng = (float)$mLng[1];
            if (is_valid_lat_lng($lat, $lng)) {
                return ["lat" => $lat, "lng" => $lng, "source" => "json_ld"];
            }
        }
        if (preg_match('/\[null,null,(-?\d+\.\d{3,}),(-?\d+\.\d{3,})\]/', $t, $matches)) {
            $lat = (float)$matches[1];
            $lng = (float)$matches[2];
            if (is_valid_lat_lng($lat, $lng)) {
                return ["lat" => $lat, "lng" => $lng, "source" => "app_init_array"];
            }
        }

        // 6. PRIORITY 6: Viewport / Camera Coordinates (@lat,lng)
        if (preg_match('/@(-?\d+\.\d+),(-?\d+\.\d+)/', $t, $matches)) {
            $lat = (float)$matches[1];
            $lng = (float)$matches[2];
            if (is_valid_lat_lng($lat, $lng)) {
                return ["lat" => $lat, "lng" => $lng, "source" => "google_maps_viewport"];
            }
        }
        if (preg_match('/staticmap\?[^"]*center=(-?\d+\.\d+)(?:%2C|,)(-?\d+\.\d+)/i', $t, $matches)) {
            $lat = (float)$matches[1];
            $lng = (float)$matches[2];
            if (is_valid_lat_lng($lat, $lng)) {
                return ["lat" => $lat, "lng" => $lng, "source" => "staticmap_center"];
            }
        }

        // 7. PRIORITY 7: Plain coordinate text
        if (preg_match('/^\s*\(?\s*(-?\d{1,3}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)\s*\)?\s*$/', $t, $matches)) {
            $lat = (float)$matches[1];
            $lng = (float)$matches[2];
            if (is_valid_lat_lng($lat, $lng)) {
                return ["lat" => $lat, "lng" => $lng, "source" => "plain_coords"];
            }
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
        // Check og:url and canonical link in HTML
        if (preg_match('/<meta\s+property=["\']og:url["\']\s+content=["\']([^"\']+)["\']/i', $body, $mOg)) {
            $resOg = extract_coords_from_text($mOg[1]);
            if ($resOg !== null) {
                echo json_encode(array_merge(["success" => true], $resOg));
                exit;
            }
        }
        if (preg_match('/<link\s+rel=["\']canonical["\']\s+href=["\']([^"\']+)["\']/i', $body, $mCanon)) {
            $resCanon = extract_coords_from_text($mCanon[1]);
            if ($resCanon !== null) {
                echo json_encode(array_merge(["success" => true], $resCanon));
                exit;
            }
        }
        if (preg_match('/<meta\s+property=["\']og:image["\']\s+content=["\']([^"\']+)["\']/i', $body, $mImg)) {
            $resImg = extract_coords_from_text($mImg[1]);
            if ($resImg !== null) {
                echo json_encode(array_merge(["success" => true], $resImg));
                exit;
            }
        }

        $resBody = extract_coords_from_text($body);
        if ($resBody !== null) {
            echo json_encode(array_merge(["success" => true], $resBody));
            exit;
        }
    }
}

echo json_encode(["success" => false, "message" => "Coordinates not found in URL."]);
?>
