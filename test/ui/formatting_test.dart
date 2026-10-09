import 'package:flutter_test/flutter_test.dart';
import 'package:iptv_flutter/ui/formatting.dart';

void main() {
  group('formatDuration', () {
    test('uses minutes and seconds below an hour', () {
      expect(formatDuration(const Duration(minutes: 2, seconds: 3)), '02:03');
    });

    test('includes hours without padding them', () {
      expect(
        formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });
  });

  group('formatBytes', () {
    test('formats bytes, kilobytes, and megabytes', () {
      expect(formatBytes(1023), '1023 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
    });
  });

  group('formatElapsed', () {
    test('uses seconds until a minute has elapsed', () {
      expect(formatElapsed(const Duration(seconds: 59)), '59s');
    });

    test('includes minutes and remaining seconds', () {
      expect(formatElapsed(const Duration(minutes: 2, seconds: 3)), '2m 3s');
    });
  });

  test('formats local date and time with fixed-width components', () {
    expect(formatDate(DateTime(2026, 9, 8, 4, 5)), '2026-09-08 04:05');
  });
}
