import 'package:flutter_test/flutter_test.dart';
import 'package:rtsp_mixer/features/monitoring/helpers/uptime_format.dart';

void main() {
  group('formatUptime', () {
    test('sub-minute renders seconds', () {
      expect(formatUptime(const Duration(seconds: 0)), '0s');
      expect(formatUptime(const Duration(seconds: 42)), '42s');
      expect(formatUptime(const Duration(seconds: 59)), '59s');
    });

    test('sub-hour renders whole minutes', () {
      expect(formatUptime(const Duration(minutes: 1)), '1m');
      expect(formatUptime(const Duration(minutes: 7, seconds: 30)), '7m');
      expect(formatUptime(const Duration(minutes: 59)), '59m');
    });

    test('an hour or more renders hours and minutes', () {
      expect(formatUptime(const Duration(hours: 1)), '1h 0m');
      expect(formatUptime(const Duration(hours: 6, minutes: 12)), '6h 12m');
      expect(
        formatUptime(const Duration(hours: 8, minutes: 5, seconds: 59)),
        '8h 5m',
      );
    });

    test('a negative duration collapses to 0s instead of rendering minus signs',
        () {
      // Clock skew or a restored session with a future startedAt. This renders
      // inside a 1-second ticker, so it has to be total.
      expect(formatUptime(const Duration(seconds: -1)), '0s');
      expect(formatUptime(const Duration(hours: -3, minutes: -20)), '0s');
    });
  });
}
