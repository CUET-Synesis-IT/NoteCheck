import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// Persists the bearer token in the platform keystore and non-sensitive
/// preferences in SharedPreferences.
class SessionStore {
  SessionStore({FlutterSecureStorage? secure}) : _secure = secure ?? const FlutterSecureStorage();

  static const _tokenKey = 'nc.token';
  static const _userKey = 'nc.user';
  static const _serverKey = 'nc.server_url';
  static const _autoCropKey = 'nc.auto_crop';
  static const _themeKey = 'nc.theme_mode';

  final FlutterSecureStorage _secure;
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async => _prefs ??= await SharedPreferences.getInstance();

  // ---------------------------------------------------------------- auth
  Future<String?> readToken() async {
    try {
      return await _secure.read(key: _tokenKey);
    } catch (_) {
      return null;
    }
  }

  Future<User?> readUser() async {
    try {
      final raw = await _secure.read(key: _userKey);
      if (raw == null) return null;
      return User.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession(String token, User user) async {
    await _secure.write(key: _tokenKey, value: token);
    await _secure.write(key: _userKey, value: jsonEncode(user.toJson()));
  }

  Future<void> saveUser(User user) => _secure.write(key: _userKey, value: jsonEncode(user.toJson()));

  Future<void> clearSession() async {
    await _secure.delete(key: _tokenKey);
    await _secure.delete(key: _userKey);
  }

  // ----------------------------------------------------------- settings
  Future<String?> readServerUrl() async => (await _p).getString(_serverKey);
  Future<void> saveServerUrl(String url) async => (await _p).setString(_serverKey, url);

  Future<bool> readAutoCrop() async => (await _p).getBool(_autoCropKey) ?? true;
  Future<void> saveAutoCrop(bool v) async => (await _p).setBool(_autoCropKey, v);

  Future<String?> readThemeMode() async => (await _p).getString(_themeKey);
  Future<void> saveThemeMode(String v) async => (await _p).setString(_themeKey, v);
}
