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

function extract_place_id($text) {
    if (empty($text)) return null;
    if (preg_match('/placeid[=\\\u003d]+([a-zA-Z0-9_\-]+)/', $text, $m)) return $m[1];
    if (preg_match('/!1s(0x[0-9a-fA-F]+:0x[0-9a-fA-F]+)/', $text, $m)) return $m[1];
    if (preg_match('/[?&]place_id=([a-zA-Z0-9_\-]+)/', $text, $m)) return $m[1];
    return null;
}

function extract_place_name_from_url($url) {
    if (empty($url)) return null;
    if (preg_match('#/maps/place/([^/@?]+)#', $url, $m)) {
        $name = urldecode(str_replace('+', ' ', $m[1]));
        if (!preg_match('/^-?\d+\.\d+,-?\d+\.\d+$/', $name)) {
            return $name;
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
        if (preg_match('/[?&](?:q|query|loc|ll)=(?:loc:)?(-?\d+\.\d+)[,+](-?\d+\.\d+)/i', $t, $matches)) {
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

        // 5. PRIORITY 5: HTML Meta Tags (Schema.org / JSON-LD)
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

        // 6. PRIORITY 6: Plain coordinate text (e.g. "13.0827, 80.2707")
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

// Step 1: Direct extraction on provided URL / text
$result = extract_coords_from_text($url);
if ($result !== null) {
    $result["place_id"] = extract_place_id($url);
    $result["place_name"] = extract_place_name_from_url($url);
    echo json_encode(array_merge(["success" => true], $result));
    exit;
}

// Step 2: Resolve shortlinks or Maps URLs safely via cURL
if (function_exists('curl_init')) {
    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
    curl_setopt($ch, CURLOPT_MAXREDIRS, 10);
    curl_setopt($ch, CURLOPT_TIMEOUT, 12);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_SSL_VERIFYHOST, 0);
    curl_setopt($ch, CURLOPT_USERAGENT, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
    $body = curl_exec($ch);
    $effectiveUrl = curl_getinfo($ch, CURLINFO_EFFECTIVE_URL);
    curl_close($ch);

    // Check effective resolved URL for explicit destination
    if (!empty($effectiveUrl)) {
        $resUrl = extract_coords_from_text($effectiveUrl);
        if ($resUrl !== null) {
            $resUrl["place_id"] = extract_place_id($effectiveUrl) ?? extract_place_id($body);
            $resUrl["place_name"] = extract_place_name_from_url($effectiveUrl);
            echo json_encode(array_merge(["success" => true, "resolved_url" => $effectiveUrl], $resUrl));
            exit;
        }
    }

    if (!empty($body)) {
        // Priority A: Google Maps Place Preview Link in HTML
        if (preg_match('/<link\s+href="(\/maps\/preview\/place[^"]+)"/i', $body, $mPlaceLink)) {
            $previewUrl = "https://www.google.com" . html_entity_decode($mPlaceLink[1]);
            $ch2 = curl_init($previewUrl);
            curl_setopt($ch2, CURLOPT_RETURNTRANSFER, true);
            curl_setopt($ch2, CURLOPT_TIMEOUT, 10);
            curl_setopt($ch2, CURLOPT_SSL_VERIFYPEER, false);
            curl_setopt($ch2, CURLOPT_SSL_VERIFYHOST, 0);
            curl_setopt($ch2, CURLOPT_USERAGENT, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
            $previewBody = curl_exec($ch2);
            curl_close($ch2);

            if (!empty($previewBody)) {
                $jsonStr = substr(trim($previewBody), 4);
                $placeData = json_decode($jsonStr, true);

                $lat = null;
                $lng = null;
                $placeId = null;
                $placeName = "";
                $address = "";

                // Extract Place ID
                if (preg_match('/placeid[=\\\u003d]+([a-zA-Z0-9_\-]+)/', $previewBody, $mId)) {
                    $placeId = $mId[1];
                } elseif (preg_match('/!1s(0x[0-9a-fA-F]+:0x[0-9a-fA-F]+)/', $effectiveUrl, $mHex)) {
                    $placeId = $mHex[1];
                }

                if (isset($placeData[4][0][2]) && isset($placeData[4][0][1])) {
                    $lat = (float)$placeData[4][0][2];
                    $lng = (float)$placeData[4][0][1];
                } elseif (preg_match('/\[null,null,(-?\d+\.\d{4,}),(-?\d+\.\d{4,})\]/', $previewBody, $mCoords)) {
                    $lat = (float)$mCoords[1];
                    $lng = (float)$mCoords[2];
                }

                if (isset($placeData[6][11]) && is_string($placeData[6][11])) {
                    $placeName = $placeData[6][11];
                }
                if (isset($placeData[6][2]) && is_array($placeData[6][2])) {
                    $address = implode(", ", array_filter($placeData[6][2]));
                }

                if ($lat !== null && $lng !== null && is_valid_lat_lng($lat, $lng)) {
                    echo json_encode([
                        "success" => true,
                        "lat" => $lat,
                        "lng" => $lng,
                        "place_id" => $placeId,
                        "place_name" => $placeName,
                        "address" => $address,
                        "source" => "google_maps_place_preview",
                        "resolved_url" => $effectiveUrl
                    ]);
                    exit;
                }
            }
        }

        // Priority B: Check canonical or og:url
        if (preg_match('/<link\s+rel=["\']canonical["\']\s+href=["\']([^"\']+)["\']/i', $body, $mCanon)) {
            $resCanon = extract_coords_from_text($mCanon[1]);
            if ($resCanon !== null) {
                $resCanon["place_id"] = extract_place_id($mCanon[1]) ?? extract_place_id($effectiveUrl);
                $resCanon["place_name"] = extract_place_name_from_url($mCanon[1]);
                echo json_encode(array_merge(["success" => true, "resolved_url" => $mCanon[1]], $resCanon));
                exit;
            }
        }
        if (preg_match('/<meta\s+property=["\']og:url["\']\s+content=["\']([^"\']+)["\']/i', $body, $mOg)) {
            $resOg = extract_coords_from_text($mOg[1]);
            if ($resOg !== null) {
                $resOg["place_id"] = extract_place_id($mOg[1]) ?? extract_place_id($effectiveUrl);
                $resOg["place_name"] = extract_place_name_from_url($mOg[1]);
                echo json_encode(array_merge(["success" => true, "resolved_url" => $mOg[1]], $resOg));
                exit;
            }
        }

        // Priority C: Explicit place geometry array [null,null,lat,lng] in body (NOT viewport)
        if (preg_match('/\[null,null,(-?\d+\.\d{4,}),(-?\d+\.\d{4,})\]/', $body, $matches)) {
            $lat = (float)$matches[1];
            $lng = (float)$matches[2];
            if (is_valid_lat_lng($lat, $lng)) {
                echo json_encode([
                    "success" => true,
                    "lat" => $lat,
                    "lng" => $lng,
                    "place_id" => extract_place_id($effectiveUrl) ?? extract_place_id($body),
                    "place_name" => extract_place_name_from_url($effectiveUrl),
                    "source" => "app_init_array",
                    "resolved_url" => $effectiveUrl
                ]);
                exit;
            }
        }
    }
}

echo json_encode([
    "success" => false,
    "message" => "Unable to identify the exact Google Maps destination. Please open the location in Google Maps and copy the location link again."
]);
?>
