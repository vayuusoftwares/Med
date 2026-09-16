import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Response;
import 'package:http/testing.dart';
import 'package:medsafelifescience/services/auth_service.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Returns a MockClient that always responds with [body] and [statusCode].
AuthService _serviceWith(String body, {int status = 200}) => AuthService(
      client: MockClient((_) async => Response(body, status,
          headers: {'content-type': 'application/json'})),
    );

/// Valid success response from the PHP backend.
String _successBody({String role = 'sales_rep'}) => jsonEncode({
      'success': true,
      'message': 'Login successful!',
      'data': {
        'user': {
          'id': 7,
          'name': 'Abi',
          'email': 'abi@test.com',
          'phone': '9999999999',
          'role': role,
          'role_label': role == 'admin' ? 'Administrator' : 'Sales Representative',
          'is_active': true,
          'created_at': '2024-01-01',
        },
        'access_token': 'wamp_token_7_1234567890',
      },
    });

// ── wampLogin ─────────────────────────────────────────────────────────────────
void main() {
  group('AuthService.wampLogin', () {
    test('success response → result.success is true', () async {
      final result = await _serviceWith(_successBody()).wampLogin(
        email: 'abi@test.com', password: 'pass123', role: 'sales_rep',
      );
      expect(result.success, isTrue);
    });

    test('success response → user is populated', () async {
      final result = await _serviceWith(_successBody()).wampLogin(
        email: 'abi@test.com', password: 'pass123', role: 'sales_rep',
      );
      expect(result.user, isNotNull);
      expect(result.user!.email, 'abi@test.com');
      expect(result.user!.id, 7);
    });

    test('success response → token is populated', () async {
      final result = await _serviceWith(_successBody()).wampLogin(
        email: 'abi@test.com', password: 'pass123', role: 'sales_rep',
      );
      expect(result.token, 'wamp_token_7_1234567890');
    });

    test('success response → message is returned', () async {
      final result = await _serviceWith(_successBody()).wampLogin(
        email: 'abi@test.com', password: 'pass123', role: 'sales_rep',
      );
      expect(result.message, 'Login successful!');
    });

    test('admin login → user.isAdmin is true', () async {
      final result = await _serviceWith(_successBody(role: 'admin')).wampLogin(
        email: 'admin@test.com', password: 'pass123', role: 'admin',
      );
      expect(result.user!.isAdmin, isTrue);
    });

    test('invalid credentials → success is false', () async {
      final body = jsonEncode({'success': false, 'message': 'Invalid credentials.'});
      final result = await _serviceWith(body).wampLogin(
        email: 'wrong@test.com', password: 'wrong', role: 'sales_rep',
      );
      expect(result.success, isFalse);
      expect(result.message, 'Invalid credentials.');
      expect(result.user, isNull);
      expect(result.token, isNull);
    });

    test('malformed JSON response → success is false with safe message', () async {
      final result = await _serviceWith('THIS IS NOT JSON').wampLogin(
        email: 'x@x.com', password: 'x', role: 'sales_rep',
      );
      expect(result.success, isFalse);
      expect(result.message, contains('unexpected response'));
    });

    test('empty body → success is false with safe message', () async {
      final result = await _serviceWith('').wampLogin(
        email: 'x@x.com', password: 'x', role: 'sales_rep',
      );
      expect(result.success, isFalse);
      expect(result.message, contains('unexpected response'));
    });

    test('xdebug HTML prefix stripped before JSON parsing', () async {
      final htmlPrefix = '<br /><b>Warning</b>: Something here</br>';
      final jsonPart = jsonEncode({'success': false, 'message': 'Invalid credentials.'});
      final result = await _serviceWith(htmlPrefix + jsonPart).wampLogin(
        email: 'x@x.com', password: 'x', role: 'sales_rep',
      );
      expect(result.success, isFalse);
      expect(result.message, 'Invalid credentials.');
    });

    test('xdebug HTML before success JSON still parses user', () async {
      final htmlPrefix = '<br/>PHP Warning: some issue<br/>';
      final result = await _serviceWith(htmlPrefix + _successBody()).wampLogin(
        email: 'abi@test.com', password: 'pass123', role: 'sales_rep',
      );
      expect(result.success, isTrue);
      expect(result.user, isNotNull);
    });

    test('network exception → cannot reach server message', () async {
      final svc = AuthService(client: MockClient((_) async => throw Exception('refused')));
      final result = await svc.wampLogin(
        email: 'x@x.com', password: 'x', role: 'sales_rep',
      );
      expect(result.success, isFalse);
      expect(result.message, contains('Could not reach server'));
    });

    test('fieldErrors is empty by default on failure', () async {
      final body = jsonEncode({'success': false, 'message': 'Bad request.'});
      final result = await _serviceWith(body).wampLogin(
        email: 'x@x.com', password: 'x', role: 'sales_rep',
      );
      expect(result.fieldErrors, isEmpty);
    });
  });

  // ── wampRegister ─────────────────────────────────────────────────────────────
  group('AuthService.wampRegister', () {
    test('success response → result.success is true', () async {
      final body = jsonEncode({'success': true, 'message': 'Registration successful!'});
      final result = await _serviceWith(body).wampRegister(
        name: 'New User', email: 'new@test.com', phone: '8888888888',
        password: 'pass123', role: 'sales_rep',
      );
      expect(result.success, isTrue);
    });

    test('duplicate email → success is false with message', () async {
      final body = jsonEncode({'success': false, 'message': 'Email already registered.'});
      final result = await _serviceWith(body).wampRegister(
        name: 'Dup User', email: 'existing@test.com', phone: '7777777777',
        password: 'pass123', role: 'sales_rep',
      );
      expect(result.success, isFalse);
      expect(result.message, 'Email already registered.');
    });

    test('network exception → cannot reach server message', () async {
      final svc = AuthService(client: MockClient((_) async => throw Exception('no conn')));
      final result = await svc.wampRegister(
        name: 'A', email: 'a@a.com', phone: '0', password: 'a', role: 'sales_rep',
      );
      expect(result.success, isFalse);
      expect(result.message, contains('Could not reach server'));
    });
  });

  // ── logout / getProfile ───────────────────────────────────────────────────
  group('AuthService.logout', () {
    test('always returns success=true', () async {
      final result = await AuthService().logout(token: 'any_token');
      expect(result.success, isTrue);
      expect(result.message, 'Logged out.');
    });
  });

  group('AuthService.getProfile', () {
    test('returns success=false (not supported)', () async {
      final result = await AuthService().getProfile(token: 'tok');
      expect(result.success, isFalse);
    });
  });

  // ── compatibility aliases ─────────────────────────────────────────────────
  group('AuthService aliases', () {
    test('login() delegates to wampLogin()', () async {
      final result = await _serviceWith(_successBody()).login(
        email: 'abi@test.com', password: 'pass123', role: 'sales_rep',
      );
      expect(result.success, isTrue);
    });

    test('register() delegates to wampRegister()', () async {
      final body = jsonEncode({'success': true, 'message': 'OK'});
      final result = await _serviceWith(body).register(
        name: 'N', email: 'e@e.com', phone: '0', password: 'p',
        passwordConfirmation: 'p', role: 'sales_rep',
      );
      expect(result.success, isTrue);
    });
  });
}
