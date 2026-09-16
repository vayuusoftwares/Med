import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../app_config.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// MapUrlService — Resilient Google Maps URL & Coordinate Extraction Service
/// ─────────────────────────────────────────────────────────────────────────────
class MapUrlService {
  /// Extract coordinates directly from a string using regex patterns without network requests.
  static Map<String, double>? extractCoordinatesFromText(String rawText) {
    if (rawText.trim().isEmpty) return null;

    final decoded = _safeUrlDecode(rawText.trim());
    final textsToTest = [rawText.trim(), decoded];

    for (final text in textsToTest) {
      // 1. Google Maps standard @lat,lng format
      final atMatch = RegExp(r'@(-?\d+\.\d+),(-?\d+\.\d+)').firstMatch(text);
      if (atMatch != null) {
        final coords = _validateCoords(atMatch.group(1), atMatch.group(2));
        if (coords != null) return coords;
      }

      // 2. Google Maps Place format (!3d<lat>!4d<lng> or !4d<lng>!3d<lat>)
      final placeMatch3d4d = RegExp(r'!3d(-?\d+\.\d+)!4d(-?\d+\.\d+)').firstMatch(text);
      if (placeMatch3d4d != null) {
        final coords = _validateCoords(placeMatch3d4d.group(1), placeMatch3d4d.group(2));
        if (coords != null) return coords;
      }

      final placeMatch4d3d = RegExp(r'!4d(-?\d+\.\d+)!3d(-?\d+\.\d+)').firstMatch(text);
      if (placeMatch4d3d != null) {
        // Note: !4d is lng, !3d is lat
        final coords = _validateCoords(placeMatch4d3d.group(2), placeMatch4d3d.group(1));
        if (coords != null) return coords;
      }

      // 3. Query params (q=, query=, loc=, center=, ll=, destination=, origin=, daddr=, saddr=)
      final queryParamMatch = RegExp(
        r'[?&](?:q|query|loc|center|ll|destination|origin|daddr|saddr)=(?:loc:)?(-?\d+\.\d+)[,+](-?\d+\.\d+)',
        caseSensitive: false,
      ).firstMatch(text);
      if (queryParamMatch != null) {
        final coords = _validateCoords(queryParamMatch.group(1), queryParamMatch.group(2));
        if (coords != null) return coords;
      }

      // 4. geo: URI scheme (e.g. geo:13.0827,80.2707)
      final geoMatch = RegExp(r'geo:(-?\d+\.\d+),(-?\d+\.\d+)', caseSensitive: false).firstMatch(text);
      if (geoMatch != null) {
        final coords = _validateCoords(geoMatch.group(1), geoMatch.group(2));
        if (coords != null) return coords;
      }

      // 5. Static map or embed image center coordinates
      final staticMapMatch = RegExp(
        r'staticmap\?[^"]*center=(-?\d+\.\d+)(?:%2C|,)(-?\d+\.\d+)',
        caseSensitive: false,
      ).firstMatch(text);
      if (staticMapMatch != null) {
        final coords = _validateCoords(staticMapMatch.group(1), staticMapMatch.group(2));
        if (coords != null) return coords;
      }

      // 6. Google Maps HTML / APP_INITIALIZATION_STATE coordinates
      final appInitMatch = RegExp(r'window\.APP_INITIALIZATION_STATE\s*=\s*\[\[\[(-?\d+\.\d+),(-?\d+\.\d+)\]').firstMatch(text);
      if (appInitMatch != null) {
        final coords = _validateCoords(appInitMatch.group(1), appInitMatch.group(2));
        if (coords != null) return coords;
      }

      final jsonArrayMatch = RegExp(r'\[null,null,(-?\d+\.\d{3,}),(-?\d+\.\d{3,})\]').firstMatch(text);
      if (jsonArrayMatch != null) {
        final coords = _validateCoords(jsonArrayMatch.group(1), jsonArrayMatch.group(2));
        if (coords != null) return coords;
      }

      // 7. Schema.org / OpenGraph meta tags
      final metaLat = RegExp(r'itemprop="latitude"[^>]*content="(-?\d+\.\d+)"', caseSensitive: false).firstMatch(text);
      final metaLng = RegExp(r'itemprop="longitude"[^>]*content="(-?\d+\.\d+)"', caseSensitive: false).firstMatch(text);
      if (metaLat != null && metaLng != null) {
        final coords = _validateCoords(metaLat.group(1), metaLng.group(1));
        if (coords != null) return coords;
      }

      // 8. Plain coordinate string (e.g. "13.0827, 80.2707" or "(13.0827, 80.2707)")
      final plainMatch = RegExp(r'^\s*\(?\s*(-?\d{1,3}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)\s*\)?\s*$').firstMatch(text);
      if (plainMatch != null) {
        final coords = _validateCoords(plainMatch.group(1), plainMatch.group(2));
        if (coords != null) return coords;
      }

      // 9. Generic lat,lng embedded in text (with at least 4 decimal places)
      final genericMatch = RegExp(r'(-?\d{1,3}\.\d{4,})\s*,\s*(-?\d{1,3}\.\d{4,})').firstMatch(text);
      if (genericMatch != null) {
        final coords = _validateCoords(genericMatch.group(1), genericMatch.group(2));
        if (coords != null) return coords;
      }
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
