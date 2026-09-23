import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:notecheck/core/api_client.dart';

Future<ApiException> catchApi(Future<dynamic> future) async {
  try {
    await future;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected an ApiException');
}

void main() {
  test('normalises base URLs', () {
    expect(ApiClient(baseUrl: '192.168.0.10:8000/').baseUrl, 'http://192.168.0.10:8000');
    expect(ApiClient(baseUrl: '  https://api.example.com//  ').baseUrl, 'https://api.example.com');
    expect(ApiClient(baseUrl: '').baseUrl, ApiClient.defaultBaseUrl);
  });

  test('adds bearer header and query parameters', () async {
    late http.Request seen;
    final client = MockClient((req) async {
      seen = req;
      return http.Response(jsonEncode({'ok': true}), 200);
    });
    final api = ApiClient(baseUrl: 'http://h:1', client: client)..token = 'tok';
    final result = await api.get('/scans', query: {'limit': 5, 'prediction': 'genuine'});
    expect(result, {'ok': true});
    expect(seen.headers['Authorization'], 'Bearer tok');
    expect(seen.url.queryParameters, {'limit': '5', 'prediction': 'genuine'});
  });

  test('surfaces FastAPI detail strings and validation errors', () async {
    final api = ApiClient(
      baseUrl: 'http://h:1',
      client: MockClient((req) async {
        if (req.url.path == '/plain') return http.Response(jsonEncode({'detail': 'Invalid email or password.'}), 401);
        return http.Response(
          jsonEncode({
            'detail': [
              {'loc': ['body', 'email'], 'msg': 'value is not a valid email address', 'type': 'value_error'}
            ]
          }),
          422,
        );
      }),
    );
    final e1 = await catchApi(api.post('/plain'));
    expect(e1.message, 'Invalid email or password.');
    expect(e1.isUnauthorized, isTrue);

    final e2 = await catchApi(api.post('/validate'));
    expect(e2.statusCode, 422);
    expect(e2.message, 'email: value is not a valid email address');
  });

  test('empty 204 bodies decode to null', () async {
    final api = ApiClient(baseUrl: 'http://h:1', client: MockClient((_) async => http.Response('', 204)));
    expect(await api.delete('/scans/1'), isNull);
  });

  test('multipart upload sends the file field', () async {
    late http.Request seen;
    final api = ApiClient(
      baseUrl: 'http://h:1',
      client: MockClient((req) async {
        seen = req;
        return http.Response(jsonEncode({'scan_id': 1}), 200);
      }),
    );
    await api.upload('/predict', bytes: Uint8List.fromList([1, 2, 3]), filename: 'n.jpg', query: {'auto_crop': false});
    expect(seen.url.queryParameters['auto_crop'], 'false');
    expect(seen.headers['content-type'], startsWith('multipart/form-data'));
    expect(utf8.decode(seen.bodyBytes, allowMalformed: true), contains('name="file"; filename="n.jpg"'));
  });
}
