import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../app_config.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// MapUrlService — Resilient Google Maps URL & Coordinate Extraction Service
/// ─────────────────────────────────────────────────────────────────────────────
class MapUrlService {
  /// Extract coordinates directly from a string using strict priority rules.
  /// Priority order:
  /// 1. Exact Google Maps place/pin coordinates (!3d<lat>!4d<lng>, !4d<lng>!3d<lat>, !1d<lng>!2d<lat>)
  /// 2. Explicit Path / Query / Destination parameters (destination=, daddr=, q=, query=, loc=, ll=, /place/<lat>,<lng>)
  /// 3. geo: URI scheme (geo:lat,lng)
  /// 4. Degrees Minutes Seconds (DMS) format (e.g. 13°04'57.7"N 80°16'14.5"E)
  /// 5. Embedded HTML Markers / JSON-LD / Place geometry arrays (markers=, itemprop=, JSON-LD, [null,null,lat,lng])
  /// 6. Viewport / Camera Coordinates (@lat,lng or staticmap center)
  /// 7. Plain coordinate text format ("13.0827, 80.2707")
  static Map<String, double>? extractCoordinatesFromText(String rawText) {
    if (rawText.trim().isEmpty) return null;

    final decoded = _safeUrlDecode(rawText.trim());
    final textsToTest = [rawText.trim(), decoded];

    for (final text in textsToTest) {
      // 1. PRIORITY 1: Exact Google Maps Place / Dropped Pin (!3d<lat>!4d<lng> or !4d<lng>!3d<lat>)
      final placeMatch3d4d = RegExp(r'!3d(-?\d+\.\d+).*?!4d(-?\d+\.\d+)').firstMatch(text);
      if (placeMatch3d4d != null) {
        final coords = _validateCoords(placeMatch3d4d.group(1), placeMatch3d4d.group(2));
        if (coords != null) return coords;
      }

      final placeMatch4d3d = RegExp(r'!4d(-?\d+\.\d+).*?!3d(-?\d+\.\d+)').firstMatch(text);
      if (placeMatch4d3d != null) {
        // Note: !4d is lng, !3d is lat
        final coords = _validateCoords(placeMatch4d3d.group(2), placeMatch4d3d.group(1));
        if (coords != null) return coords;
      }

      // Directions / Route destination pin (!1d<lng>!2d<lat> or !2d<lat>!1d<lng>)
      final placeMatch1d2d = RegExp(r'!1d(-?\d+\.\d+).*?!2d(-?\d+\.\d+)').firstMatch(text);
      if (placeMatch1d2d != null) {
        // !1d is lng, !2d is lat
        final coords = _validateCoords(placeMatch1d2d.group(2), placeMatch1d2d.group(1));
        if (coords != null) return coords;
      }

      // 2. PRIORITY 2: Explicit Place in Path & Target Parameters
      // /maps/place/<lat>,<lng> or /maps/search/<lat>,<lng> or /maps/dir/.../<lat>,<lng>
      final pathCoordsMatch = RegExp(
        r'/maps/(?:place|search|dir(?:/[^/]+)?)/(-?\d+\.\d+)[,+](-?\d+\.\d+)',
        caseSensitive: false,
      ).firstMatch(text);
      if (pathCoordsMatch != null) {
        final coords = _validateCoords(pathCoordsMatch.group(1), pathCoordsMatch.group(2));
        if (coords != null) return coords;
      }

      // Handles destination=, daddr= (directions destination)
      final destMatch = RegExp(
        r'[?&](?:destination|daddr)=(-?\d+\.\d+)[,+](-?\d+\.\d+)',
        caseSensitive: false,
      ).firstMatch(text);
      if (destMatch != null) {
        final coords = _validateCoords(destMatch.group(1), destMatch.group(2));
        if (coords != null) return coords;
      }

      // Handles q=loc:lat,lng or q=lat,lng, query=lat,lng, loc=lat,lng, ll=lat,lng
      final queryParamMatch = RegExp(
        r'[?&](?:q|query|loc|ll|saddr)=(?:loc:)?(-?\d+\.\d+)[,+](-?\d+\.\d+)',
        caseSensitive: false,
      ).firstMatch(text);
      if (queryParamMatch != null) {
        final coords = _validateCoords(queryParamMatch.group(1), queryParamMatch.group(2));
        if (coords != null) return coords;
      }

      // Handles lat=...&lng=... or lat=...&lon=...
      final latParam = RegExp(r'[?&]lat=(-?\d+\.\d+)', caseSensitive: false).firstMatch(text);
      final lngParam = RegExp(r'[?&](?:lng|lon)=(-?\d+\.\d+)', caseSensitive: false).firstMatch(text);
      if (latParam != null && lngParam != null) {
        final coords = _validateCoords(latParam.group(1), lngParam.group(1));
        if (coords != null) return coords;
      }

      // 3. PRIORITY 3: geo: URI scheme (e.g. geo:13.0827,80.2707)
      final geoMatch = RegExp(r'geo:(-?\d+\.\d+),(-?\d+\.\d+)', caseSensitive: false).firstMatch(text);
      if (geoMatch != null) {
        final coords = _validateCoords(geoMatch.group(1), geoMatch.group(2));
        if (coords != null) return coords;
      }

      // 4. PRIORITY 4: Degrees Minutes Seconds (DMS) format
      final dmsCoords = _parseDms(text);
      if (dmsCoords != null) return dmsCoords;

      // 5. PRIORITY 5: Embedded Static Map Markers, JSON-LD, & Place arrays
      final markerParamMatch = RegExp(r'markers=([^&"'"'"']+)', caseSensitive: false).firstMatch(text);
      if (markerParamMatch != null) {
        final markerVal = markerParamMatch.group(1)!;
        final markerCoords = RegExp(r'(-?\d+\.\d+)(?:%2C|,)(-?\d+\.\d+)').allMatches(markerVal);
        if (markerCoords.isNotEmpty) {
          final lastCoord = markerCoords.last;
          final coords = _validateCoords(lastCoord.group(1), lastCoord.group(2));
          if (coords != null) return coords;
        }
      }

      // Schema.org / OpenGraph meta tags
      final metaLat = RegExp(r'itemprop=["\x27]latitude["\x27][^>]*content=["\x27](-?\d+\.\d+)["\x27]', caseSensitive: false).firstMatch(text);
      final metaLng = RegExp(r'itemprop=["\x27]longitude["\x27][^>]*content=["\x27](-?\d+\.\d+)["\x27]', caseSensitive: false).firstMatch(text);
      if (metaLat != null && metaLng != null) {
        final coords = _validateCoords(metaLat.group(1), metaLng.group(1));
        if (coords != null) return coords;
      }

      // JSON-LD "latitude": 13.0827, "longitude": 80.2707
      final jsonLdLat = RegExp(r'"latitude"\s*:\s*"?(-?\d+\.\d+)"?', caseSensitive: false).firstMatch(text);
      final jsonLdLng = RegExp(r'"longitude"\s*:\s*"?(-?\d+\.\d+)"?', caseSensitive: false).firstMatch(text);
      if (jsonLdLat != null && jsonLdLng != null) {
        final coords = _validateCoords(jsonLdLat.group(1), jsonLdLng.group(1));
        if (coords != null) return coords;
      }

      // ICBM or geo.position meta tags
      final geoPos = RegExp(r'<meta[^>]*content=["\x27](-?\d+\.\d+)[,;\s]+(-?\d+\.\d+)["\x27][^>]*(?:name|property)=["\x27](?:geo\.position|ICBM)["\x27]', caseSensitive: false).firstMatch(text) ??
          RegExp(r'<meta[^>]*(?:name|property)=["\x27](?:geo\.position|ICBM)["\x27][^>]*content=["\x27](-?\d+\.\d+)[,;\s]+(-?\d+\.\d+)["\x27]', caseSensitive: false).firstMatch(text);
      if (geoPos != null) {
        final coords = _validateCoords(geoPos.group(1), geoPos.group(2));
        if (coords != null) return coords;
      }

      // Place geometry array: [null,null,lat,lng]
      final jsonArrayMatch = RegExp(r'\[null,null,(-?\d+\.\d{3,}),(-?\d+\.\d{3,})\]').firstMatch(text);
      if (jsonArrayMatch != null) {
        final coords = _validateCoords(jsonArrayMatch.group(1), jsonArrayMatch.group(2));
        if (coords != null) return coords;
      }

      // 6. PRIORITY 6: Viewport / Camera Coordinates (@lat,lng) - only when no pin was found
      final atMatch = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(text);
      if (atMatch != null) {
        final coords = _validateCoords(atMatch.group(1), atMatch.group(2));
        if (coords != null) return coords;
      }

      // Static map center fallback (only if no marker was found)
      final staticMapCenterMatch = RegExp(
        r'staticmap\?[^"]*center=(-?\d+\.\d+)(?:%2C|,)(-?\d+\.\d+)',
        caseSensitive: false,
      ).firstMatch(text);
      if (staticMapCenterMatch != null) {
        final coords = _validateCoords(staticMapCenterMatch.group(1), staticMapCenterMatch.group(2));
        if (coords != null) return coords;
      }

      // 7. PRIORITY 7: Plain coordinate string (e.g. "13.0827, 80.2707" or "(13.0827, 80.2707)")
      final plainMatch = RegExp(r'^\s*\(?\s*(-?\d{1,3}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)\s*\)?\s*$').firstMatch(text);
      if (plainMatch != null) {
        final coords = _validateCoords(plainMatch.group(1), plainMatch.group(2));
        if (coords != null) return coords;
      }

      // Generic lat,lng embedded in text (with at least 4 decimal places)
      final genericMatch = RegExp(r'(-?\d{1,3}\.\d{4,})\s*,\s*(-?\d{1,3}\.\d{4,})').firstMatch(text);
      if (genericMatch != null) {
        final coords = _validateCoords(genericMatch.group(1), genericMatch.group(2));
        if (coords != null) return coords;
      }
    }

    return null;
  }

  /// Parses Degrees Minutes Seconds (DMS) string to decimal lat/lng
  static Map<String, double>? _parseDms(String text) {
    final dmsRegex = RegExp(
      r'''(\d{1,3})[°\s]+(\d{1,2}(?:\.\d+)?)['′\s]*(?:(\d{1,2}(?:\.\d+)?)[″"\s]*)?([NSns])[,+\s]+(\d{1,3})[°\s]+(\d{1,2}(?:\.\d+)?)['′\s]*(?:(\d{1,2}(?:\.\d+)?)[″"\s]*)?([EWew])''',
    );
    final match = dmsRegex.firstMatch(text);
    if (match != null) {
      try {
        final latDeg = double.parse(match.group(1)!);
        final latMin = double.parse(match.group(2)!);
        final latSec = match.group(3) != null && match.group(3)!.isNotEmpty ? double.parse(match.group(3)!) : 0.0;
        final latDir = match.group(4)!.toUpperCase();

        final lngDeg = double.parse(match.group(5)!);
        final lngMin = double.parse(match.group(6)!);
        final lngSec = match.group(7) != null && match.group(7)!.isNotEmpty ? double.parse(match.group(7)!) : 0.0;
        final lngDir = match.group(8)!.toUpperCase();

        var lat = latDeg + (latMin / 60.0) + (latSec / 3600.0);
        if (latDir == 'S') lat = -lat;

        var lng = lngDeg + (lngMin / 60.0) + (lngSec / 3600.0);
        if (lngDir == 'W') lng = -lng;

        if (_isValidLatLng(lat, lng)) {
          return {'lat': lat, 'lng': lng};
        }
      } catch (_) {}
    }
    return null;
  }

  /// Resolves any Google Maps URL, shortlink (maps.app.goo.gl, goo.gl), or coordinate text.
  /// First tries instant regex extraction, then follows HTTP redirects on-device, then queries backend fallback.
  static Future<Map<String, double>?> resolveMapUrl(
    String rawInput, {
    Duration timeout = const Duration(seconds: 8),
    bool tryBackend = true,
  }) async {
    final input = rawInput.trim();
    if (input.isEmpty) return null;

    // Step 1: Instant local parsing (no network required)
    final localResult = extractCoordinatesFromText(input);
    if (localResult != null) {
      debugPrint('[MapUrlService] Coordinates parsed locally: $localResult');
      return localResult;
    }

    // If input is not a URL, nothing more to resolve
    var uri = Uri.tryParse(input);
    if (uri == null || (!input.startsWith('http://') && !input.startsWith('https://'))) {
      if (input.startsWith('maps.app.goo.gl/') || input.startsWith('goo.gl/maps/')) {
        uri = Uri.tryParse('https://$input');
      } else {
        return null;
      }
    }

    // Step 2: On-device redirect resolution via HTTP GET
    if (uri != null) {
      try {
        final client = http.Client();
        try {
          final request = http.Request('GET', uri)
            ..followRedirects = true
            ..maxRedirects = 10
            ..headers.addAll({
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
              'Accept-Language': 'en-US,en;q=0.9',
            });

          final streamedRes = await client.send(request).timeout(timeout);
          final res = await http.Response.fromStream(streamedRes);

          // Check final resolved URL
          final finalUrl = streamedRes.request?.url.toString() ?? '';
          if (finalUrl.isNotEmpty) {
            final coordsFromFinalUrl = extractCoordinatesFromText(finalUrl);
            if (coordsFromFinalUrl != null) {
              debugPrint('[MapUrlService] Coordinates resolved from final URL: $coordsFromFinalUrl');
              return coordsFromFinalUrl;
            }
          }

          // Check redirect location header if present
          final locationHeader = res.headers['location'];
          if (locationHeader != null && locationHeader.isNotEmpty) {
            final coordsFromLocation = extractCoordinatesFromText(locationHeader);
            if (coordsFromLocation != null) {
              debugPrint('[MapUrlService] Coordinates resolved from Location header: $coordsFromLocation');
              return coordsFromLocation;
            }
          }

          // Check response body HTML
          if (res.body.isNotEmpty) {
            // Check OpenGraph URL / Canonical Link
            final ogUrlMatch = RegExp(r'<meta\s+property=["\x27]og:url["\x27]\s+content=["\x27]([^"\x27]+)["\x27]', caseSensitive: false).firstMatch(res.body);
            if (ogUrlMatch != null) {
              final coords = extractCoordinatesFromText(ogUrlMatch.group(1)!);
              if (coords != null) return coords;
            }

            final canonicalMatch = RegExp(r'<link\s+rel=["\x27]canonical["\x27]\s+href=["\x27]([^"\x27]+)["\x27]', caseSensitive: false).firstMatch(res.body);
            if (canonicalMatch != null) {
              final coords = extractCoordinatesFromText(canonicalMatch.group(1)!);
              if (coords != null) return coords;
            }

            final ogImageMatch = RegExp(r'<meta\s+property=["\x27]og:image["\x27]\s+content=["\x27]([^"\x27]+)["\x27]', caseSensitive: false).firstMatch(res.body);
            if (ogImageMatch != null) {
              final coords = extractCoordinatesFromText(ogImageMatch.group(1)!);
              if (coords != null) return coords;
            }

            final coordsFromBody = extractCoordinatesFromText(res.body);
            if (coordsFromBody != null) {
              debugPrint('[MapUrlService] Coordinates extracted from response body: $coordsFromBody');
              return coordsFromBody;
            }
          }
        } finally {
          client.close();
        }
      } catch (e) {
        debugPrint('[MapUrlService] On-device redirect resolution warning: $e');
      }
    }

    // Step 3: Backend URL Resolver fallback (if backend is reachable)
    if (tryBackend) {
      for (final host in AppConfig.allHosts) {
        try {
          final targetUrl = Uri.parse('$host/backend/resolve_map_url.php');
          final response = await http
              .post(
                targetUrl,
                headers: AppConfig.headers,
                body: jsonEncode({'url': input}),
              )
              .timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data['success'] == true && data['lat'] != null && data['lng'] != null) {
              final lat = (data['lat'] as num).toDouble();
              final lng = (data['lng'] as num).toDouble();
              if (_isValidLatLng(lat, lng)) {
                debugPrint('[MapUrlService] Coordinates resolved via backend: {lat: $lat, lng: $lng}');
                return {'lat': lat, 'lng': lng};
              }
            }
          }
        } catch (_) {
          // Continue to next host
        }
      }
    }

    return null;
  }

  static String _safeUrlDecode(String str) {
    try {
      return Uri.decodeFull(str);
    } catch (_) {
      return str;
    }
  }

  static Map<String, double>? _validateCoords(String? latStr, String? lngStr) {
    if (latStr == null || lngStr == null) return null;
    final lat = double.tryParse(latStr);
    final lng = double.tryParse(lngStr);
    if (lat != null && lng != null && _isValidLatLng(lat, lng)) {
      return {'lat': lat, 'lng': lng};
    }
    return null;
  }

  static bool _isValidLatLng(double lat, double lng) {
    return lat >= -90.0 && lat <= 90.0 && lng >= -180.0 && lng <= 180.0 && (lat != 0.0 || lng != 0.0);
  }
}
