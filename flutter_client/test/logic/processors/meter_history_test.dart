import 'package:flutter_client/logic/processors/meter_history.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const interval = Duration(milliseconds: 50);
  const frame = Duration(microseconds: 6944); // a 144 Hz display
  const loud = 0.8;
  const quiet = 0.1;
  const tolerance = 0.01;
  const columnsToFill = 10;
  const half = 0.5;
  const capacity = 8;
  const settledColumns = 3;
  const holdProbe = Duration(milliseconds: 300);
  const fallWindow = Duration(seconds: 2);
  const wraps = 3;

  MeterHistory history() => MeterHistory(capacity: capacity);

  /// Advances [h] from [from] to exactly [to], one display frame at a time.
  Duration run(MeterHistory h, Duration from, Duration to) {
    var t = from;
    while (t + frame < to) {
      t += frame;
      h.advance(t);
    }
    h.advance(to);

    return to;
  }

  Matcher level(double value) => closeTo(value, tolerance);

  group('MeterHistory', () {
    test('settles one column per interval whatever the frame rate', () {
      final h = history()..reset(Duration.zero);
      h.level = loud;
      run(h, Duration.zero, interval * settledColumns);

      expect(h.columnAt(0), level(loud));
      expect(h.columnAt(settledColumns - 1), level(loud));
      expect(h.columnAt(settledColumns), 0);
    });

    test('older columns keep their recorded level as new ones arrive', () {
      final h = history()..reset(Duration.zero);
      h.level = loud;
      var t = run(h, Duration.zero, interval);
      h.level = quiet;
      t = run(h, t, t + interval * 2);

      expect(h.columnAt(0), level(quiet));
      expect(h.columnAt(2), level(loud));
    });

    test('fraction tracks progress toward the next column', () {
      final h = history()..reset(Duration.zero);
      h.advance(interval * half);

      expect(h.fraction, closeTo(half, tolerance));
    });

    test('the live level eases toward the target rather than jumping', () {
      final h = history()..reset(Duration.zero);
      h.level = loud;
      h.advance(frame);

      expect(h.live, greaterThan(0));
      expect(h.live, lessThan(loud));
      run(h, frame, interval * columnsToFill);
      expect(h.live, closeTo(loud, tolerance));
    });

    test('the peak holds, then falls but never below the live level', () {
      final h = history()..reset(Duration.zero);
      h.level = loud;
      var t = run(h, Duration.zero, interval * columnsToFill);
      final held = h.peak;
      h.level = quiet;
      t = run(h, t, t + holdProbe);
      expect(h.peak, held);

      run(h, t, t + fallWindow);
      expect(h.peak, closeTo(h.live, tolerance));
    });

    test('ring wraps without losing the newest columns', () {
      final h = history()..reset(Duration.zero);
      h.level = loud;
      run(h, Duration.zero, interval * (capacity * wraps));

      for (var age = 0; age < capacity; age++) {
        expect(h.columnAt(age), level(loud));
      }
    });

    test('reset clears levels, live and peak', () {
      final h = history()..reset(Duration.zero);
      h.level = loud;
      final t = run(h, Duration.zero, interval * columnsToFill);
      h.reset(t);

      expect(h.columnAt(0), 0);
      expect(h.live, 0);
      expect(h.peak, 0);
    });
  });
}
