import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/models.dart';

class AdminProvider extends ChangeNotifier {
  AdminProvider({required this.api});

  final ApiClient api;

  AdminOverview? _overview;
  List<User> _users = const [];
  List<Scan> _recent = const [];
  bool _loading = false;
  String? _error;
  int _days = 14;

  AdminOverview? get overview => _overview;
  List<User> get users => _users;
  List<Scan> get recentScans => _recent;
  bool get loading => _loading;
  String? get error => _error;
  int get days => _days;

  Future<void> setDays(int d) async {
    _days = d;
    await refresh();
  }

  Future<void> refresh() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        api.get('/admin/overview', query: {'days': _days}),
        api.get('/admin/users'),
        api.get('/admin/scans', query: {'limit': 15}),
      ]);
      _overview = AdminOverview.fromJson(results[0] as Map<String, dynamic>);
      _users = (results[1] as List).map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
      _recent = PagedScans.fromJson(results[2] as Map<String, dynamic>).items;
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> setRole(User user, String role) async {
    final json = await api.patch('/admin/users/${user.id}/role', body: {'role': role});
    final updated = User.fromJson(json as Map<String, dynamic>);
    _users = [for (final u in _users) u.id == updated.id ? updated : u];
    notifyListeners();
  }

  Future<void> deleteUser(User user) async {
    await api.delete('/admin/users/${user.id}');
    _users = _users.where((u) => u.id != user.id).toList();
    notifyListeners();
    await refresh();
  }

  void reset() {
    _overview = null;
    _users = const [];
    _recent = const [];
    _error = null;
    notifyListeners();
  }
}
