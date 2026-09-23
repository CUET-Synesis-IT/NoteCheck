import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notecheck/core/formatters.dart';
import 'package:notecheck/models/models.dart';

void main() {
  group('Prediction.fromJson', () {
    test('parses the /predict payload and decodes the preview image', () {
      final jpeg = base64Encode([0xFF, 0xD8, 0xFF, 0xD9]);
      final p = Prediction.fromJson({
        'scan_id': 7,
        'prediction': 'counterfeit',
        'confidence': 0.8123,
        'probabilities': {'counterfeit': 0.8123, 'genuine': 0.1877},
        'decision_threshold': 0.5,
        'inference_time_ms': 88.4,
        'note_detected_and_cropped': true,
        'cropped_banknote_base64': 'data:image/jpeg;base64,$jpeg',
        'created_at': '2026-09-17T18:00:31.484844Z',
      });
      expect(p.scanId, 7);
      expect(p.isGenuine, isFalse);
      expect(p.label, 'counterfeit');
      expect(p.confidence, closeTo(0.8123, 1e-9));
      expect(p.genuineProb, closeTo(0.1877, 1e-9));
      expect(p.wasCropped, isTrue);
      expect(p.noteImage, isNotNull);
      expect(p.noteImage!.first, 0xFF);
      expect(p.createdAt!.isUtc, isTrue);
    });

    test('tolerates a missing image', () {
      final p = Prediction.fromJson({
        'scan_id': 1,
        'prediction': 'genuine',
        'confidence': 0.9,
        'probabilities': {'counterfeit': 0.1, 'genuine': 0.9},
        'decision_threshold': 0.5,
        'inference_time_ms': 10,
        'note_detected_and_cropped': false,
        'cropped_banknote_base64': null,
        'created_at': null,
      });
      expect(p.noteImage, isNull);
      expect(p.isGenuine, isTrue);
      expect(p.createdAt, isNull);
    });
  });

  test('PagedScans.hasMore reflects total', () {
    final page = PagedScans.fromJson({
      'items': [
        {'id': 3, 'prediction': 'genuine', 'confidence': 0.9, 'genuine_prob': 0.9, 'counterfeit_prob': 0.1, 'latency_ms': 5, 'was_cropped': false, 'has_image': true, 'created_at': '2026-01-01T00:00:00Z'},
      ],
      'total': 5,
      'limit': 1,
      'offset': 0,
    });
    expect(page.items.single.label, 'Genuine');
    expect(page.hasMore, isTrue);
  });

  test('User initials and admin flag', () {
    expect(User.fromJson({'id': 1, 'name': 'Md. Saminul Amin', 'email': 'a@b.co', 'role': 'admin'}).initials, 'MA');
    expect(User.fromJson({'id': 1, 'name': 'Ayesha', 'email': 'a@b.co', 'role': 'user'}).initials, 'A');
    expect(User.fromJson({'id': 1, 'name': 'x', 'email': 'a@b.co', 'role': 'admin'}).isAdmin, isTrue);
  });

  test('AdminOverview parses by_day', () {
    final o = AdminOverview.fromJson({
      'total_scans': 3,
      'genuine_count': 1,
      'counterfeit_count': 2,
      'counterfeit_rate': 0.6667,
      'total_users': 2,
      'admin_count': 1,
      'scans_last_24h': 3,
      'avg_latency_ms': 70.5,
      'by_day': [
        {'date': '2026-09-16', 'count': 0, 'counterfeit': 0},
        {'date': '2026-09-17', 'count': 3, 'counterfeit': 2},
      ],
    });
    expect(o.byDay.length, 2);
    expect(o.byDay.last.genuine, 1);
  });

  group('Fmt', () {
    test('percent and ms', () {
      expect(Fmt.percent(0.9788), '97.9%');
      expect(Fmt.percent(0.5, decimals: 0), '50%');
      expect(Fmt.ms(88.4), '88 ms');
      expect(Fmt.ms(1530), '1.53 s');
    });
    test('relative time', () {
      expect(Fmt.relative(null), 'never');
      expect(Fmt.relative(DateTime.now().subtract(const Duration(seconds: 5))), 'just now');
      expect(Fmt.relative(DateTime.now().subtract(const Duration(minutes: 3))), '3 min ago');
    });
  });
}
