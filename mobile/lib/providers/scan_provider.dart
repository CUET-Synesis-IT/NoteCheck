import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../models/models.dart';

enum ScanFilter { all, genuine, counterfeit }

/// Runs analyses and keeps the signed-in user's history and stats.
class ScanProvider extends ChangeNotifier {
  ScanProvider({required this.api, required this.onUnauthorized});

  final ApiClient api;
  final Future<void> Function() onUnauthorized;

  static const pageSize = 20;

  bool _analyzing = false;
  Prediction? _lastPrediction;
  Uint8List? _lastOriginal;

  final List<Scan> _scans = [];
  int _total = 0;
  bool _loadingHistory = false;
  bool _loadingMore = false;
  String? _historyError;
  ScanFilter _filter = ScanFilter.all;

  UserStats _stats = UserStats.empty;

  bool get analyzing => _analyzing;
  Prediction? get lastPrediction => _lastPrediction;
  Uint8List? get lastOriginal => _lastOriginal;

  List<Scan> get scans => List.unmodifiable(_scans);
  int get total => _total;
  bool get loadingHistory => _loadingHistory;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _scans.length < _total;
  String? get historyError => _historyError;
  ScanFilter get filter => _filter;
  UserStats get stats => _stats;

  // -------------------------------------------------------------- analyse
  Future<Prediction> analyze(Uint8List bytes, {required bool autoCrop, String filename = 'note.jpg'}) async {
    _analyzing = true;
    notifyListeners();
    try {
      final json = await api.upload(
        '/predict',
        bytes: bytes,
        filename: filename,
        query: {'auto_crop': autoCrop, 'include_image': true},
      );
      final prediction = Prediction.fromJson(json as Map<String, dynamic>);
      _lastPrediction = prediction;
      _lastOriginal = bytes;
      // keep history/stats fresh without another round-trip for the list
      unawaited(refreshHistory());
      unawaited(refreshStats());
      return prediction;
    } on ApiException catch (e) {
      if (e.isUnauthorized) await onUnauthorized();
      rethrow;
    } finally {
      _analyzing = false;
      notifyListeners();
    }
  }

  void clearLast() {
    _lastPrediction = null;
    _lastOriginal = null;
    notifyListeners();
  }

  // -------------------------------------------------------------- history
  Future<void> setFilter(ScanFilter f) async {
    if (_filter == f) return;
    _filter = f;
    await refreshHistory();
  }

  Future<void> refreshHistory() async {
    _loadingHistory = true;
    _historyError = null;
    notifyListeners();
    try {
      final page = await _fetchPage(0);
      _scans
        ..clear()
        ..addAll(page.items);
      _total = page.total;
    } on ApiException catch (e) {
      _historyError = e.message;
      if (e.isUnauthorized) await onUnauthorized();
    } finally {
      _loadingHistory = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (_loadingMore || _loadingHistory || !hasMore) return;
    _loadingMore = true;
    notifyListeners();
    try {
      final page = await _fetchPage(_scans.length);
      _scans.addAll(page.items.where((s) => _scans.every((e) => e.id != s.id)));
      _total = page.total;
    } on ApiException catch (e) {
      _historyError = e.message;
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  Future<PagedScans> _fetchPage(int offset) async {
    final json = await api.get('/scans', query: {
      'limit': pageSize,
      'offset': offset,
      if (_filter != ScanFilter.all) 'prediction': _filter.name,
    });
    return PagedScans.fromJson(json as Map<String, dynamic>);
  }

  Future<void> deleteScan(int id) async {
    await api.delete('/scans/$id');
    final removed = _scans.indexWhere((s) => s.id == id);
    if (removed >= 0) {
      _scans.removeAt(removed);
      _total = (_total - 1).clamp(0, 1 << 30);
    }
    if (_lastPrediction?.scanId == id) clearLast();
    notifyListeners();
    unawaited(refreshStats());
  }

  Future<void> refreshStats() async {
    try {
      final json = await api.get('/scans/stats');
      _stats = UserStats.fromJson(json as Map<String, dynamic>);
      notifyListeners();
    } on ApiException catch (e) {
      if (e.isUnauthorized) await onUnauthorized();
    }
  }

  void reset() {
    _scans.clear();
    _total = 0;
    _stats = UserStats.empty;
    _historyError = null;
    _filter = ScanFilter.all;
    clearLast();
  }
}
