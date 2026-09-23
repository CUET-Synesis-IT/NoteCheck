import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Error surfaced to the UI. [statusCode] is null for transport failures.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isUnauthorized => statusCode == 401;
  bool get isNetwork => statusCode == null;

  @override
  String toString() => message;
}

/// Thin JSON/multipart client for the NoteCheck API.
///
/// Holds the mutable base URL and bearer token so every provider shares one
/// configuration. Anything that changes them (settings, sign-in) writes here.
class ApiClient {
  ApiClient({required String baseUrl, http.Client? client})
      : _baseUrl = _normalize(baseUrl),
        _client = client ?? http.Client();

  static const defaultBaseUrl = 'http://10.0.2.2:8000';
  static const _timeout = Duration(seconds: 25);
  static const _uploadTimeout = Duration(seconds: 90);

  final http.Client _client;
  String _baseUrl;
  String? token;

  String get baseUrl => _baseUrl;
  set baseUrl(String value) => _baseUrl = _normalize(value);

  static String _normalize(String url) {
    var u = url.trim();
    if (u.isEmpty) return defaultBaseUrl;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Map<String, String> get authHeaders => token == null ? const {} : {'Authorization': 'Bearer $token'};

  Uri uri(String path, [Map<String, dynamic>? query]) {
    final q = query?.map((k, v) => MapEntry(k, v.toString()));
    return Uri.parse('$_baseUrl$path').replace(queryParameters: q == null || q.isEmpty ? null : q);
  }

  String scanImageUrl(int scanId) => uri('/scans/$scanId/image').toString();

  // ------------------------------------------------------------ verbs
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _client.get(uri(path, query), headers: _headers()));

  Future<dynamic> post(String path, {Object? body}) =>
      _send(() => _client.post(uri(path), headers: _headers(json: true), body: jsonEncode(body ?? {})));

  Future<dynamic> patch(String path, {Object? body}) =>
      _send(() => _client.patch(uri(path), headers: _headers(json: true), body: jsonEncode(body ?? {})));

  Future<dynamic> delete(String path) => _send(() => _client.delete(uri(path), headers: _headers()));

  Future<dynamic> upload(
    String path, {
    required Uint8List bytes,
    required String filename,
    Map<String, dynamic>? query,
  }) {
    return _send(() async {
      final request = http.MultipartRequest('POST', uri(path, query))
        ..headers.addAll(_headers())
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
      final streamed = await _client.send(request).timeout(_uploadTimeout);
      return http.Response.fromStream(streamed);
    }, timeout: _uploadTimeout);
  }

  Map<String, String> _headers({bool json = false}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json',
        ...authHeaders,
      };

  Future<dynamic> _send(Future<http.Response> Function() run, {Duration timeout = _timeout}) async {
    http.Response response;
    try {
      response = await run().timeout(timeout);
    } on TimeoutException {
      throw ApiException('The server took too long to respond.');
    } on SocketException catch (e) {
      throw ApiException('Cannot reach the server at $_baseUrl.\n${e.osError?.message ?? e.message}');
    } on http.ClientException catch (e) {
      throw ApiException('Connection failed: ${e.message}');
    } on HandshakeException {
      throw ApiException('TLS handshake failed. Check the server address.');
    }

    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      if (response.bodyBytes.isEmpty) return null;
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    throw ApiException(_extractDetail(response), statusCode: status);
  }

  static String _extractDetail(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      final detail = body is Map ? body['detail'] : null;
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        // FastAPI validation errors: [{loc: [...], msg: ...}]
        final first = detail.first;
        if (first is Map && first['msg'] != null) {
          final loc = (first['loc'] as List?)?.where((e) => e != 'body').join('.');
          final msg = first['msg'].toString().replaceFirst(RegExp(r'^Value error, '), '');
          return loc == null || loc.isEmpty ? msg : '$loc: $msg';
        }
      }
    } catch (_) {}
    return switch (response.statusCode) {
      401 => 'Please sign in again.',
      403 => 'You do not have permission to do that.',
      404 => 'Not found.',
      413 => 'The image is too large.',
      429 => 'Too many attempts. Please wait a moment.',
      503 => 'The server is starting up or the model is not loaded.',
      _ => 'Request failed (${response.statusCode}).',
    };
  }

  void close() => _client.close();
}
