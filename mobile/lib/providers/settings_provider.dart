import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../models/models.dart';
import '../services/session_store.dart';

/// Server address, scan defaults, theme, and the periodic health probe.
class SettingsProvider extends ChangeNotifier {
  SettingsProvider({required this.api, required this.store});

  final ApiClient api;
  final SessionStore store;

  bool _loaded = false;
  bool _autoCrop = true;
  ThemeMode _themeMode = ThemeMode.dark;
  ServerHealth _health = ServerHealth.unknown;
  bool _checking = false;
  Timer? _timer;

  bool get loaded => _loaded;
  String get serverUrl => api.baseUrl;
  bool get autoCrop => _autoCrop;
  ThemeMode get themeMode => _themeMode;
  ServerHealth get health => _health;
  bool get checking => _checking;

  Future<void> load() async {
    final url = await store.readServerUrl();
    if (url != null && url.isNotEmpty) api.baseUrl = url;
    _autoCrop = await store.readAutoCrop();
    _themeMode = _parseTheme(await store.readThemeMode());
    _loaded = true;
    notifyListeners();
    startHealthPolling();
  }

  Future<void> setServerUrl(String url) async {
    api.baseUrl = url;
    await store.saveServerUrl(api.baseUrl);
    _health = ServerHealth.unknown;
    notifyListeners();
    await checkHealth();
  }

  Future<void> setAutoCrop(bool value) async {
    _autoCrop = value;
    notifyListeners();
    await store.saveAutoCrop(value);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    await store.saveThemeMode(mode.name);
  }

  // --------------------------------------------------------------- health
  void startHealthPolling({Duration every = const Duration(seconds: 15)}) {
    _timer?.cancel();
    checkHealth();
    _timer = Timer.periodic(every, (_) => checkHealth());
  }

  void stopHealthPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<ServerHealth> checkHealth() async {
    if (_checking) return _health;
    _checking = true;
    notifyListeners();
    try {
      final json = await api.get('/health');
      _health = ServerHealth.fromJson(json as Map<String, dynamic>);
    } on ApiException catch (e) {
      _health = ServerHealth(online: false, modelLoaded: false, error: e.message);
    } catch (e) {
      _health = ServerHealth(online: false, modelLoaded: false, error: e.toString());
    } finally {
      _checking = false;
      notifyListeners();
    }
    return _health;
  }

  static ThemeMode _parseTheme(String? v) => switch (v) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      };

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
