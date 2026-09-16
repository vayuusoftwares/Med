import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/user_model.dart';
import '../app_config.dart';

/// Wraps the API response into a typed result so callers never deal with raw maps.
class AuthResult {
  final bool success;
  final String message;
  final User? user;
  final String? token;

  final Map<String, List<String>> fieldErrors;

  const AuthResult({
    required this.success,
    required this.message,
    this.user,
    this.token,
    this.fieldErrors = const {},
  });
}

class AuthService {
  /// Injectable HTTP client — defaults to a real client in production.
  /// Pass a [MockClient] in tests to control server responses.
  final http.Client _client;

  AuthService({http.Client? client}) : _client = client ?? http.Client();

  // ─────────────────────────────────────────────
  // Public: WAMP/ngrok Login
  // ─────────────────────────────────────────────
  Future<AuthResult> wampLogin({
    required String email,
    required String password,
    required String role,
  }) async {
    final body = jsonEncode({'email': email, 'password': password, 'role': role});

    for (final host in AppConfig.allHosts) {
      try {
        final url = '$host/backend/login.php';
        debugPrint('[API] Request started: $url');
        final response = await _client
            .post(
              Uri.parse(url),
              headers: AppConfig.headers,
              body: body,
            )
            .timeout(const Duration(seconds: 8));
        debugPrint('[API] Response code: ${response.statusCode}');
        final result = _parseResponse(response);
        if (result.success) {
          AppConfig.setWorkingHost(host);
          return result;
        }
        if (response.statusCode == 200) return result; // server responded — stop trying
      } catch (e) {
        debugPrint('[API] Request failed on $host: $e');
      }
    }

    return const AuthResult(
      success: false,
      message: 'Could not reach server. Check your internet connection or WAMP status.',
    );
  }

  // ─────────────────────────────────────────────
  // Public: WAMP/ngrok Register
  // ─────────────────────────────────────────────
  Future<AuthResult> wampRegister({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String role,
  }) async {
    final body = jsonEncode({
      'name': name, 'email': email, 'phone': phone,
      'password': password, 'role': role,
    });

    for (final host in AppConfig.allHosts) {
      try {
        final response = await _client
            .post(
              Uri.parse('$host/backend/register.php'),
              headers: AppConfig.headers,
              body: body,
            )
            .timeout(const Duration(seconds: 10));
        final result = _parseResponse(response);
        if (result.success) return result;
        if (response.statusCode == 200) return result;
      } catch (_) {
        // Try next host
      }
    }

    return const AuthResult(
      success: false,
      message: 'Could not reach server. Check your internet connection or WAMP status.',
    );
  }

  // ─────────────────────────────────────────────
  // Compatibility aliases
  // ─────────────────────────────────────────────
  Future<AuthResult> login({
    required String email,
    required String password,
    required String role,
  }) => wampLogin(email: email, password: password, role: role);

  Future<AuthResult> register({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String passwordConfirmation,
    required String role,
  }) => wampRegister(name: name, email: email, phone: phone, password: password, role: role);

  Future<AuthResult> logout({required String token}) async =>
      const AuthResult(success: true, message: 'Logged out.');

  Future<AuthResult> getProfile({required String token}) async =>
      const AuthResult(success: false, message: 'Not supported.');

  // ─────────────────────────────────────────────
  // Private: Parse PHP response (strips xdebug HTML)
  // ─────────────────────────────────────────────
  AuthResult _parseResponse(http.Response response) {
    String raw = response.body.trim();

    // Strip any PHP warnings / xdebug HTML before the JSON object
    final jsonStart = raw.indexOf('{');
    if (jsonStart < 0) {
      return const AuthResult(
        success: false,
        message: 'Server returned an unexpected response. Please try again.',
      );
    }
    raw = raw.substring(jsonStart);

    Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return const AuthResult(
        success: false,
        message: 'Server returned an unexpected response. Please try again.',
      );
    }

    final bool success  = json['success'] == true;
    final String message = json['message'] as String? ?? 'An unknown error occurred.';

    if (success) {
      final data     = json['data'] as Map<String, dynamic>?;
      final userJson = data?['user'] as Map<String, dynamic>?;
      final token    = data?['access_token'] as String?;

      return AuthResult(
        success: true,
        message: message,
        user:    userJson != null ? User.fromJson(userJson) : null,
        token:   token,
      );
    }

    return AuthResult(success: false, message: message);
  }
}
