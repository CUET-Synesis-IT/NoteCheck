import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notecheck/core/api_client.dart';
import 'package:notecheck/main.dart';
import 'package:notecheck/services/session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';

/// In-memory replacement for the keystore so widget tests never touch a platform channel.
class _MemorySecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> _data = {};

  @override
  Future<bool> containsKey({required String key, required Map<String, String> options}) async => _data.containsKey(key);

  @override
  Future<void> delete({required String key, required Map<String, String> options}) async => _data.remove(key);

  @override
  Future<void> deleteAll({required Map<String, String> options}) async => _data.clear();

  @override
  Future<String?> read({required String key, required Map<String, String> options}) async => _data[key];

  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) async => Map.of(_data);

  @override
  Future<void> write({required String key, required String value, required Map<String, String> options}) async => _data[key] = value;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStoragePlatform.instance = _MemorySecureStorage();
  });

  http.Client fakeServer({bool loggedInOk = true}) => MockClient((req) async {
        switch (req.url.path) {
          case '/health':
            return http.Response(
              jsonEncode({'status': 'online', 'version': '3.0.0', 'model_loaded': true, 'device': 'cpu', 'tta_enabled': true, 'decision_threshold': 0.5, 'max_upload_mb': 12}),
              200,
            );
          case '/auth/login':
            if (!loggedInOk) return http.Response(jsonEncode({'detail': 'Invalid email or password.'}), 401);
            return http.Response(
              jsonEncode({
                'access_token': 'tok',
                'token_type': 'bearer',
                'expires_in_days': 30,
                'user': {'id': 1, 'name': 'Test User', 'email': 'user@test.example', 'role': 'user', 'created_at': '2026-01-01T00:00:00Z'},
              }),
              200,
            );
          case '/auth/me':
            return http.Response(jsonEncode({'id': 1, 'name': 'Test User', 'email': 'user@test.example', 'role': 'user', 'created_at': '2026-01-01T00:00:00Z'}), 200);
          case '/scans':
            return http.Response(jsonEncode({'items': [], 'total': 0, 'limit': 20, 'offset': 0}), 200);
          case '/scans/stats':
            return http.Response(jsonEncode({'total_scans': 0, 'genuine_count': 0, 'counterfeit_count': 0, 'counterfeit_rate': 0, 'avg_confidence': 0, 'avg_latency_ms': 0}), 200);
        }
        return http.Response(jsonEncode({'detail': 'Not found.'}), 404);
      });

  /// Advance past every timed animation/delay so no timer outlives the test.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  Future<void> pumpApp(WidgetTester tester, {bool loggedInOk = true}) async {
    final api = ApiClient(baseUrl: 'http://h:1', client: fakeServer(loggedInOk: loggedInOk));
    await tester.pumpWidget(NoteCheckApp(api: api, store: SessionStore(secure: const FlutterSecureStorage())));
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('shows login when no session is stored', (tester) async {
    await pumpApp(tester);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsWidgets);
    await settle(tester);
  });

  testWidgets('validates the form before submitting', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    await settle(tester);
  });

  testWidgets('signs in and lands on the scan screen', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'user@test.example');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'UserPass123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Hello, Test'), findsOneWidget);
    expect(find.text('Add a banknote photo'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    await settle(tester);
  });

  testWidgets('shows the server error on a bad password', (tester) async {
    await pumpApp(tester, loggedInOk: false);
    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'user@test.example');
    await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'wrong');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Invalid email or password.'), findsOneWidget);
    await settle(tester);
  });
}
