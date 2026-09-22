import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../app_config.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// ExtractedMapDestination — Detailed Google Maps Destination Information
/// ─────────────────────────────────────────────────────────────────────────────
class ExtractedMapDestination {
  final double lat;
  final double lng;
  final String? placeName;
  final String? address;
  final String? placeId;
  final String extractionMethod;
  final String originalUrl;
  final String resolvedUrl;

  const ExtractedMapDestination({
    required this.lat,
    required this.lng,
    this.placeName,
    this.address,
    this.placeId,
    required this.extractionMethod,
    required this.originalUrl,
    required this.resolvedUrl,
  });

  Map<String, double> toLatLngMap() => {'lat': lat, 'lng': lng};

  @override
  String toString() =>
      'ExtractedMapDestination(lat: $lat, lng: $lng, placeName: $placeName, address: $address, placeId: $placeId, method: $extractionMethod)';
}

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
  /// 5. Embedded HTML Markers / JSON-LD / Place geometry arrays (itemprop=, JSON-LD)
  /// 6. Plain coordinate text format ("13.0827, 80.2707")
  ///
  /// STRICT RULE: NEVER extracts map viewport / camera coordinates (@lat,lng or staticmap center).
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
        r'[?&](?:q|query|loc|ll)=(?:loc:)?(-?\d+\.\d+)[,+](-?\d+\.\d+)',
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

      // 5. PRIORITY 5: Schema.org / JSON-LD meta tags
      final metaLat = RegExp(r'itemprop=["\x27]latitude["\x27][^>]*content=["\x27](-?\d+\.\d+)["\x27]', caseSensitive: false).firstMatch(text);
      final metaLng = RegExp(r'itemprop=["\x27]longitude["\x27][^>]*content=["\x27](-?\d+\.\d+)["\x27]', caseSensitive: false).firstMatch(text);
      if (metaLat != null && metaLng != null) {
        final coords = _validateCoords(metaLat.group(1), metaLng.group(1));
        if (coords != null) return coords;
      }

      final jsonLdLat = RegExp(r'"latitude"\s*:\s*"?(-?\d+\.\d+)"?', caseSensitive: false).firstMatch(text);
      final jsonLdLng = RegExp(r'"longitude"\s*:\s*"?(-?\d+\.\d+)"?', caseSensitive: false).firstMatch(text);
      if (jsonLdLat != null && jsonLdLng != null) {
        final coords = _validateCoords(jsonLdLat.group(1), jsonLdLng.group(1));
        if (coords != null) return coords;
      }

      // 6. PRIORITY 6: Plain coordinate string (e.g. "13.0827, 80.2707" or "(13.0827, 80.2707)")
      final plainMatch = RegExp(r'^\s*\(?\s*(-?\d{1,3}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)\s*\)?\s*$').firstMatch(text);
      if (plainMatch != null) {
        final coords = _validateCoords(plainMatch.group(1), plainMatch.group(2));
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

  /// Resolves any Google Maps URL or short link into an [ExtractedMapDestination]
  /// with exact destination coordinates, place name, and address.
  static Future<ExtractedMapDestination?> resolveLocation(
    String rawInput, {
    Duration timeout = const Duration(seconds: 12),
    bool tryBackend = true,
  }) async {
    final input = rawInput.trim();
    if (input.isEmpty) return null;

    debugPrint('[MapUrlService] Resolving location from input URL: $input');

    // Step 1: Instant local parsing on input text if already contains coordinates
    final localResult = extractCoordinatesFromText(input);
    if (localResult != null) {
      final lat = localResult['lat']!;
      final lng = localResult['lng']!;
      debugPrint('[MapUrlService] Coordinates parsed directly from input: {lat: $lat, lng: $lng}');
      final address = await reverseGeocode(lat, lng);
      final dest = ExtractedMapDestination(
        lat: lat,
        lng: lng,
        address: address,
        placeId: _extractPlaceId(input),
        extractionMethod: 'direct_coordinate_input',
        originalUrl: input,
        resolvedUrl: input,
      );
      _logResolution(dest);
      return dest;
    }

    // Step 2: Validate and format URL
    var uri = Uri.tryParse(input);
    if (uri == null || (!input.startsWith('http://') && !input.startsWith('https://'))) {
      if (input.startsWith('maps.app.goo.gl/') || input.startsWith('goo.gl/maps/')) {
        uri = Uri.tryParse('https://$input');
      } else {
        return null;
      }
    }

    String finalResolvedUrl = input;

    // Step 3: On-device redirect resolution & Google Place preview parsing
    if (uri != null) {
      try {
        final client = http.Client();
        try {
          final request = http.Request('GET', uri)
            ..followRedirects = true
            ..maxRedirects = 10
            ..headers.addAll({
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
              'Accept-Language': 'en-US,en;q=0.9',
            });

          final streamedRes = await client.send(request).timeout(timeout);
          final res = await http.Response.fromStream(streamedRes);

          finalResolvedUrl = streamedRes.request?.url.toString() ?? input;
          debugPrint('[MapUrlService] Resolved URL: $finalResolvedUrl');

          // Check if resolved final URL contains explicit coordinates
          final coordsFromFinalUrl = extractCoordinatesFromText(finalResolvedUrl);
          if (coordsFromFinalUrl != null) {
            final lat = coordsFromFinalUrl['lat']!;
            final lng = coordsFromFinalUrl['lng']!;
            debugPrint('[MapUrlService] Destination coordinates extracted from final URL: {lat: $lat, lng: $lng}');
            final address = await reverseGeocode(lat, lng);
            final dest = ExtractedMapDestination(
              lat: lat,
              lng: lng,
              address: address,
              placeId: _extractPlaceId(finalResolvedUrl) ?? _extractPlaceId(input),
              extractionMethod: 'resolved_url_destination',
              originalUrl: input,
              resolvedUrl: finalResolvedUrl,
            );
            _logResolution(dest);
            return dest;
          }

          // Check response body HTML
          if (res.body.isNotEmpty) {
            // Priority A: Google Maps Place Preview Link in HTML
            final previewLinkMatch = RegExp(
              r'<link\s+href="(/maps/preview/place[^"]+)"',
              caseSensitive: false,
            ).firstMatch(res.body);

            if (previewLinkMatch != null) {
              final rawPath = previewLinkMatch.group(1)!;
              final decodedPath = _safeHtmlUnescape(rawPath);
              final previewUri = Uri.parse('https://www.google.com$decodedPath');

              debugPrint('[MapUrlService] Found Place Preview link, fetching place data...');
              try {
                final previewRes = await http.get(
                  previewUri,
                  headers: {
                    'User-Agent':
                        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                    'Accept-Language': 'en-US,en;q=0.9',
                  },
                ).timeout(const Duration(seconds: 8));

                if (previewRes.statusCode == 200 && previewRes.body.isNotEmpty) {
                  final parsedDest = _parsePlacePreviewResponse(
                    previewRes.body,
                    originalUrl: input,
                    resolvedUrl: finalResolvedUrl,
                  );
                  if (parsedDest != null) {
                    debugPrint(
                      '[MapUrlService] Destination extracted via Place Preview: lat=${parsedDest.lat}, lng=${parsedDest.lng}, place=${parsedDest.placeName}, address=${parsedDest.address}',
                    );
                    _logResolution(parsedDest);
                    return parsedDest;
                  }
                }
              } catch (e) {
                debugPrint('[MapUrlService] Place preview request error: $e');
              }
            }

            // Priority B: Check canonical or og:url
            final canonicalMatch = RegExp(
              r'<link\s+rel=["\x27]canonical["\x27]\s+href=["\x27]([^"\x27]+)["\x27]',
              caseSensitive: false,
            ).firstMatch(res.body);
            if (canonicalMatch != null) {
              final coords = extractCoordinatesFromText(canonicalMatch.group(1)!);
              if (coords != null) {
                final lat = coords['lat']!;
                final lng = coords['lng']!;
                final address = await reverseGeocode(lat, lng);
                final dest = ExtractedMapDestination(
                  lat: lat,
                  lng: lng,
                  address: address,
                  placeId: _extractPlaceId(canonicalMatch.group(1)!) ?? _extractPlaceId(finalResolvedUrl),
                  extractionMethod: 'canonical_link_destination',
                  originalUrl: input,
                  resolvedUrl: canonicalMatch.group(1)!,
                );
                _logResolution(dest);
                return dest;
              }
            }

            final ogUrlMatch = RegExp(
              r'<meta\s+property=["\x27]og:url["\x27]\s+content=["\x27]([^"\x27]+)["\x27]',
              caseSensitive: false,
            ).firstMatch(res.body);
            if (ogUrlMatch != null) {
              final coords = extractCoordinatesFromText(ogUrlMatch.group(1)!);
              if (coords != null) {
                final lat = coords['lat']!;
                final lng = coords['lng']!;
                final address = await reverseGeocode(lat, lng);
                final dest = ExtractedMapDestination(
                  lat: lat,
                  lng: lng,
                  address: address,
                  placeId: _extractPlaceId(ogUrlMatch.group(1)!) ?? _extractPlaceId(finalResolvedUrl),
                  extractionMethod: 'og_url_destination',
                  originalUrl: input,
                  resolvedUrl: ogUrlMatch.group(1)!,
                );
                _logResolution(dest);
                return dest;
              }
            }

            // Priority C: Explicit place geometry array [null,null,lat,lng] in HTML
            final jsonArrayMatch = RegExp(r'\[null,null,(-?\d+\.\d{4,}),(-?\d+\.\d{4,})\]').firstMatch(res.body);
            if (jsonArrayMatch != null) {
              final coords = _validateCoords(jsonArrayMatch.group(1), jsonArrayMatch.group(2));
              if (coords != null) {
                final lat = coords['lat']!;
                final lng = coords['lng']!;
                final address = await reverseGeocode(lat, lng);
                final dest = ExtractedMapDestination(
                  lat: lat,
                  lng: lng,
                  address: address,
                  placeId: _extractPlaceId(finalResolvedUrl) ?? _extractPlaceId(res.body),
                  extractionMethod: 'place_geometry_array',
                  originalUrl: input,
                  resolvedUrl: finalResolvedUrl,
                );
                _logResolution(dest);
                return dest;
              }
            }
          }
        } finally {
          client.close();
        }
      } catch (e) {
        debugPrint('[MapUrlService] On-device resolution note: $e');
      }
    }

    // Step 4: Backend URL Resolver fallback
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
              .timeout(const Duration(seconds: 6));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data['success'] == true && data['lat'] != null && data['lng'] != null) {
              final lat = (data['lat'] as num).toDouble();
              final lng = (data['lng'] as num).toDouble();
              if (_isValidLatLng(lat, lng)) {
                String? address = data['address'] as String?;
                final placeName = data['place_name'] as String?;
                final placeId = data['place_id'] as String?;
                if (address == null || address.trim().isEmpty) {
                  address = await reverseGeocode(lat, lng);
                }
                debugPrint('[MapUrlService] Resolved via backend: lat=$lat, lng=$lng, place=$placeName, placeId=$placeId');
                final dest = ExtractedMapDestination(
                  lat: lat,
                  lng: lng,
                  placeName: placeName != null && placeName.trim().isNotEmpty ? placeName.trim() : null,
                  address: address != null && address.trim().isNotEmpty ? address.trim() : null,
                  placeId: placeId != null && placeId.trim().isNotEmpty ? placeId.trim() : null,
                  extractionMethod: data['source'] as String? ?? 'backend_resolver',
                  originalUrl: input,
                  resolvedUrl: data['resolved_url'] as String? ?? finalResolvedUrl,
                );
                _logResolution(dest);
                return dest;
              }
            }
          }
        } catch (_) {
          // Continue to next host
        }
      }
    }

    debugPrint('[MapUrlService] Could not resolve exact destination from: $input');
    return null;
  }

  /// Parses the response from /maps/preview/place?... endpoint
  static ExtractedMapDestination? _parsePlacePreviewResponse(
    String body, {
    required String originalUrl,
    required String resolvedUrl,
  }) {
    try {
      var trimmed = body.trim();
      if (trimmed.startsWith(")]}'")) {
        trimmed = trimmed.substring(4).trim();
      }

      final dynamic data = json.decode(trimmed);
      if (data is List) {
        double? lat;
        double? lng;
        String? placeName;
        String? address;

        // Coordinates at data[4][0] -> [distance, lng, lat]
        if (data.length > 4 && data[4] is List && (data[4] as List).isNotEmpty) {
          final firstItem = data[4][0];
          if (firstItem is List && firstItem.length >= 3) {
            final possibleLng = (firstItem[1] as num?)?.toDouble();
            final possibleLat = (firstItem[2] as num?)?.toDouble();
            if (possibleLat != null && possibleLng != null && _isValidLatLng(possibleLat, possibleLng)) {
              lat = possibleLat;
              lng = possibleLng;
            }
          }
        }

        // Fallback: search for [null,null,lat,lng] in raw preview body
        if (lat == null || lng == null) {
          final m = RegExp(r'\[null,null,(-?\d+\.\d{4,}),(-?\d+\.\d{4,})\]').firstMatch(body);
          if (m != null) {
            final coords = _validateCoords(m.group(1), m.group(2));
            if (coords != null) {
              lat = coords['lat'];
              lng = coords['lng'];
            }
          }
        }

        // Place Name at data[6][11] or data[6][0]
        if (data.length > 6 && data[6] is List) {
          final list6 = data[6] as List;
          if (list6.length > 11 && list6[11] is String && (list6[11] as String).trim().isNotEmpty) {
            placeName = (list6[11] as String).trim();
          }

          // Address lines at data[6][2]
          if (list6.length > 2 && list6[2] is List) {
            final addrList = (list6[2] as List).whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty);
            if (addrList.isNotEmpty) {
              address = addrList.join(', ');
            }
          }
        }

        // Extract Place ID if present
        final placeId = _extractPlaceId(body) ?? _extractPlaceId(resolvedUrl);

        if (lat != null && lng != null && _isValidLatLng(lat, lng)) {
          return ExtractedMapDestination(
            lat: lat,
            lng: lng,
            placeName: placeName,
            address: address,
            placeId: placeId,
            extractionMethod: 'google_maps_place_preview',
            originalUrl: originalUrl,
            resolvedUrl: resolvedUrl,
          );
        }
      }
    } catch (e) {
      debugPrint('[MapUrlService] Error parsing place preview JSON: $e');
    }
    return null;
  }

  /// Logs the 7 debug points required for Google Maps location extraction
  static void _logResolution(ExtractedMapDestination dest) {
    debugPrint('Original URL: ${dest.originalUrl}');
    debugPrint('Resolved URL: ${dest.resolvedUrl}');
    debugPrint('Place ID: ${dest.placeId ?? 'N/A'}');
    debugPrint('Extraction method: ${dest.extractionMethod}');
    debugPrint('Final destination: ${dest.placeName ?? dest.address ?? 'Detected Location'}');
    debugPrint('Final latitude: ${dest.lat}');
    debugPrint('Final longitude: ${dest.lng}');
  }

  /// Extracts Google Place ID (ChIJ... or hex 0x...:0x...) from URLs or HTML
  static String? _extractPlaceId(String text) {
    if (text.isEmpty) return null;
    final m1 = RegExp(r'placeid[=\\u003d]+([a-zA-Z0-9_\-]+)').firstMatch(text);
    if (m1 != null) return m1.group(1);
    final m2 = RegExp(r'!1s(0x[0-9a-fA-F]+:0x[0-9a-fA-F]+)').firstMatch(text);
    if (m2 != null) return m2.group(1);
    final m3 = RegExp(r'[?&]place_id=([a-zA-Z0-9_\-]+)').firstMatch(text);
    if (m3 != null) return m3.group(1);
    return null;
  }

  /// Reverse geocode coordinates using OpenStreetMap Nominatim
  static Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final uri = Uri.parse('https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng');
      final res = await http.get(
        uri,
        headers: {
          'User-Agent': 'MedSafeLifeScience/1.0 (contact@medsafe.com)',
          'Accept-Language': 'en',
        },
      ).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final displayName = data['display_name'] as String?;
        if (displayName != null && displayName.trim().isNotEmpty) {
          return displayName.trim();
        }
      }
    } catch (_) {}
    return null;
  }

  /// Backward-compatible coordinate resolver returning {'lat': lat, 'lng': lng}
  static Future<Map<String, double>?> resolveMapUrl(
    String rawInput, {
    Duration timeout = const Duration(seconds: 12),
    bool tryBackend = true,
  }) async {
    final dest = await resolveLocation(rawInput, timeout: timeout, tryBackend: tryBackend);
    return dest?.toLatLngMap();
  }

  static String _safeHtmlUnescape(String str) {
    return str
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
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

