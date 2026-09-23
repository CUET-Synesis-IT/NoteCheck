import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/models.dart';
import '../services/session_store.dart';

enum AuthStatus { unknown, signedOut, signedIn }

class AuthProvider extends ChangeNotifier {
  AuthProvider({required this.api, required this.store});

  final ApiClient api;
  final SessionStore store;

  AuthStatus _status = AuthStatus.unknown;
  User? _user;
  bool _busy = false;

  AuthStatus get status => _status;
  User? get user => _user;
  bool get busy => _busy;
  bool get isAdmin => _user?.isAdmin ?? false;
  bool get signedIn => _status == AuthStatus.signedIn;

  /// Restore a saved session. Works offline: the cached user is shown until
  /// the server can be reached; a 401 clears it.
  Future<void> bootstrap() async {
    final token = await store.readToken();
    final cached = await store.readUser();
    if (token == null || cached == null) {
      _set(AuthStatus.signedOut, null);
      return;
    }
    api.token = token;
    _set(AuthStatus.signedIn, cached);
    try {
      final me = await api.get('/auth/me');
      final fresh = User.fromJson(me as Map<String, dynamic>);
      await store.saveUser(fresh);
      _set(AuthStatus.signedIn, fresh);
    } on ApiException catch (e) {
      if (e.isUnauthorized) await signOut();
      // network errors keep the cached session
    }
  }

  Future<void> signIn(String email, String password) => _authenticate(
        '/auth/login',
        {'email': email.trim(), 'password': password},
      );

  Future<void> register(String name, String email, String password) => _authenticate(
        '/auth/register',
        {'name': name.trim(), 'email': email.trim(), 'password': password},
      );

  Future<void> _authenticate(String path, Map<String, dynamic> body) async {
    _busy = true;
    notifyListeners();
    try {
      final json = await api.post(path, body: body);
      final session = AuthSession.fromJson(json as Map<String, dynamic>);
      api.token = session.token;
      await store.saveSession(session.token, session.user);
      _set(AuthStatus.signedIn, session.user);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    api.token = null;
    await store.clearSession();
    _set(AuthStatus.signedOut, null);
  }

  Future<void> refreshProfile() async {
    if (!signedIn) return;
    try {
      final me = await api.get('/auth/me');
      final fresh = User.fromJson(me as Map<String, dynamic>);
      await store.saveUser(fresh);
      _set(AuthStatus.signedIn, fresh);
    } on ApiException catch (e) {
      if (e.isUnauthorized) await signOut();
    }
  }

  Future<void> updateName(String name) async {
    final json = await api.patch('/auth/me', body: {'name': name.trim()});
    final fresh = User.fromJson(json as Map<String, dynamic>);
    await store.saveUser(fresh);
    _set(AuthStatus.signedIn, fresh);
  }

  Future<void> changePassword(String current, String next) =>
      api.post('/auth/change-password', body: {'current_password': current, 'new_password': next});

  /// Called by other providers when any request answers 401.
  Future<void> handleUnauthorized() async {
    if (signedIn) await signOut();
  }

  void _set(AuthStatus status, User? user) {
    _status = status;
    _user = user;
    notifyListeners();
  }
}
