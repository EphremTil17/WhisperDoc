import 'package:flutter_client/logic/formatters/clock_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClockTime.minutesSeconds', () {
    test('pads seconds and does not pad minutes', () {
      expect(ClockTime.minutesSeconds(Duration.zero), '0:00');
      expect(ClockTime.minutesSeconds(const Duration(seconds: 7)), '0:07');
      expect(
        ClockTime.minutesSeconds(const Duration(minutes: 12, seconds: 5)),
        '12:05',
      );
    });

    test('drops sub-second precision', () {
      expect(
        ClockTime.minutesSeconds(const Duration(seconds: 59, milliseconds: 999)),
        '0:59',
      );
    });
  });

  group('ClockTime.ago', () {
    test('reads as plain relative time', () {
      expect(ClockTime.ago(const Duration(seconds: 40)), 'just now');
      expect(ClockTime.ago(const Duration(minutes: 1)), '1 min ago');
      expect(ClockTime.ago(const Duration(minutes: 59)), '59 min ago');
      expect(ClockTime.ago(const Duration(hours: 3, minutes: 5)), '3 h ago');
    });
  });
}
