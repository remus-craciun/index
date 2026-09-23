import 'package:flutter_test/flutter_test.dart';
import 'package:index_app/core/network/server_url.dart';
import 'package:index_app/core/time.dart';

void main() {
  group('normalizeServerUrl', () {
    final cases = {
      '192.168.1.5:8080': 'http://192.168.1.5:8080',
      ' localhost:8080/ ': 'http://localhost:8080',
      'index.example.com': 'https://index.example.com',
      'https://index.example.com/api/v1/': 'https://index.example.com',
      'http://index.example.com': 'http://index.example.com',
      'https://example.com/index/': 'https://example.com/index',
    };
    cases.forEach((input, want) {
      test(input, () => expect(normalizeServerUrl(input), want));
    });

    test('rejects garbage', () {
      expect(() => normalizeServerUrl(''), throwsFormatException);
      expect(() => normalizeServerUrl('ftp://x.com'), throwsFormatException);
    });
  });

  group('time', () {
    test('formatStamp is fixed-width UTC millis', () {
      expect(formatStamp(DateTime.utc(2026, 1, 2, 3, 4, 5, 6, 789)), '2026-01-02T03:04:05.006Z');
    });

    test('editStamp is later than a future previous stamp', () {
      const future = '2999-01-01T00:00:00.000Z';
      expect(editStamp(future), '2999-01-01T00:00:00.001Z');
      expect(editStamp('2000-01-01T00:00:00.000Z').compareTo('2000-01-01T00:00:00.000Z'), greaterThan(0));
    });

    test('dateKey round-trips', () {
      expect(dateKey(parseDateKey('2026-03-09')), '2026-03-09');
    });
  });
}
