import 'dart:convert';
import 'package:flutter/foundation.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// app_config.dart — Central Production & Server Configuration
/// ─────────────────────────────────────────────────────────────────────────────
class AppConfig {
  // ── 1. NGROK HTTPS Development Tunnel URL ──────────────────────────────────
  static const String ngrokUrl = 'https://overjoyed-strode-bountiful.ngrok-free.dev';

  // ── 2. Your PC / Server local IP ──────────────────────────────────────────
  static const String localIp = 'http://192.168.0.100'; // Local LAN IP for Wi-Fi devices

  // ── 3. Toggle: true = use NGROK tunnel ────────────────────────────────────
  static const bool useNgrok = true;

  // Cached working base URL after successful health check
  static String? _cachedWorkingHost;

  // ── Resolved base URL ──
  static String get baseUrl {
    if (_cachedWorkingHost != null && _cachedWorkingHost!.isNotEmpty) {
      return _cachedWorkingHost!;
    }
    if (kIsWeb) {
      final origin = Uri.base.origin;
      if (origin.isNotEmpty && !origin.startsWith('file://')) {
        return origin;
      }
    }
    return useNgrok ? ngrokUrl : localIp;
  }

  static void setWorkingHost(String host) {
    _cachedWorkingHost = host;
    debugPrint('[ApiConfig] Active host cached: $host');
  }

  // ── All fallback hosts tried in order ────────────────────────────────────
  static List<String> get allHosts {
    final webOrigin = kIsWeb ? Uri.base.origin : null;
    final list = <String>[];

    if (_cachedWorkingHost != null && _cachedWorkingHost!.isNotEmpty) {
      list.add(_cachedWorkingHost!);
    }

    if (webOrigin != null && webOrigin.isNotEmpty && !webOrigin.startsWith('file://')) {
      list.add(webOrigin);
    }
    // 1. Primary NGROK Tunnel URL
    if (useNgrok && ngrokUrl.isNotEmpty) {
      list.add(ngrokUrl);
    }
    // 2. Direct LAN IPs (Wi-Fi connected devices)
    list.add('http://192.168.0.100');
    list.add('http://192.168.0.102');
    // 3. Android Emulator fallback
    list.add('http://10.0.2.2');
    // 4. Localhost fallbacks (Web/PC)
    list.addAll([
      'http://127.0.0.1',
      'http://localhost',
      localIp,
    ]);
    return list.toSet().toList(); // Unique hosts
  }

  // ── Production headers ───────────────────────────────────────────────────
  static Map<String, String> get headers => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'ngrok-skip-browser-warning': 'true',
  };

  /// Safe JSON decoding that strips potential BOM or whitespace
  static dynamic safeJsonDecode(String body) {
    var cleaned = body.trim();
    if (cleaned.startsWith('\uFEFF')) {
      cleaned = cleaned.substring(1).trim();
    }
    return json.decode(cleaned);
  }

  // ── 5. Destination Arrival & Checkout Proximity Configuration ───────────
  /// Allowed destination arrival/checkout proximity radius in meters (<= 15.0m allowed, > 15.0m blocked)
  static const double destinationRadiusMeters = 15.0;

  /// Target duration allowed inside destination before overtime kicks in (5 minutes = 300 seconds)
  static const int destinationTargetDurationSeconds = 300;

  /// Required continuous stable duration inside the destination radius for auto-checkout (60 seconds)
  static const int autoCheckoutStableSeconds = 60;
}

