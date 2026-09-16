import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

/// A thin wrapper around SharedPreferences for persisting the auth token
/// and cached user data between app launches.
class StorageService {
  static const _keyToken = 'auth_token';
  static const _keyUser = 'auth_user';

  // ─────────────────────────────────────────────
  // Token
  // ─────────────────────────────────────────────

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  Future<void> deleteToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
  }

  // ─────────────────────────────────────────────
  // User
  // ─────────────────────────────────────────────

  Future<void> saveUser(User user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUser, jsonEncode(user.toJson()));
  }

  Future<User?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyUser);
    if (raw == null) return null;
    try {
      return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUser);
  }

  // ─────────────────────────────────────────────
  // Clear all (logout)
  // ─────────────────────────────────────────────

  Future<void> clearAll() async {
    await Future.wait([deleteToken(), deleteUser()]);
  }
}
