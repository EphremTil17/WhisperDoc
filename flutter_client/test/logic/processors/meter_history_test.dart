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
  const newerColumns = 2;
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
      h.record(loud, Duration.zero);
      run(h, Duration.zero, interval * settledColumns);

      final heard = level(loud);
      expect(h.columnAt(0), heard);
      expect(h.columnAt(settledColumns - 1), heard);
      expect(h.columnAt(settledColumns), 0);
    });

    test('older columns keep their recorded level as new ones arrive', () {
      final h = history()..reset(Duration.zero);
      h.record(loud, Duration.zero);
      var t = run(h, Duration.zero, interval);
      h.record(quiet, t);
      t = run(h, t, t + interval * newerColumns);

      expect(h.columnAt(0), level(quiet));
      expect(h.columnAt(newerColumns), level(loud));
    });

    test('fraction tracks progress toward the next column', () {
      final h = history()..reset(Duration.zero);
      h.advance(interval * half);

      expect(h.fraction, closeTo(half, tolerance));
    });

    test('the live level eases toward the target rather than jumping', () {
      final h = history()..reset(Duration.zero);
      h.record(loud, Duration.zero);
      h.advance(frame);

      expect(h.live, greaterThan(0));
      expect(h.live, lessThan(loud));
      run(h, frame, interval * columnsToFill);
      expect(h.live, closeTo(loud, tolerance));
    });

    test('the peak holds, then falls but never below the live level', () {
      final h = history()..reset(Duration.zero);
      h.record(loud, Duration.zero);
      var t = run(h, Duration.zero, interval * columnsToFill);
      final held = h.peak;
      h.record(quiet, t);
      t = run(h, t, t + holdProbe);
      expect(h.peak, held);

      run(h, t, t + fallWindow);
      expect(h.peak, closeTo(h.live, tolerance));
    });

    test('ring wraps without losing the newest columns', () {
      final h = history()..reset(Duration.zero);
      h.record(loud, Duration.zero);
      run(h, Duration.zero, interval * (capacity * wraps));

      for (var age = 0; age < capacity; age++) {
        expect(h.columnAt(age), level(loud));
      }
    });

    test('levels recorded without frames keep their own columns', () {
      // A panel covers the meter: its ticker is muted but audio keeps
      // arriving. The gap must show what was heard, not the last level.
      final h = history()..reset(Duration.zero);
      for (var i = 0; i < capacity; i++) {
        h.record(i.isEven ? loud : quiet, interval * i);
      }
      h.advance(interval * capacity);

      for (var age = 0; age < capacity; age++) {
        expect(h.columnAt(age), level(age.isEven ? quiet : loud));
      }
    });

    test('a gap longer than the ring keeps the newest columns', () {
      final h = history()..reset(Duration.zero);
      h.record(loud, Duration.zero);
      h.advance(interval * (capacity * wraps * wraps));

      final heard = level(loud);
      expect(h.columnAt(0), heard);
      expect(h.columnAt(capacity - 1), heard);
      expect(h.fraction, closeTo(0, tolerance));
    });

    test('reset clears levels, live and peak', () {
      final h = history()..reset(Duration.zero);
      h.record(loud, Duration.zero);
      final t = run(h, Duration.zero, interval * columnsToFill);
      h.reset(t);

      expect(h.columnAt(0), 0);
      expect(h.live, 0);
      expect(h.peak, 0);
    });

    test('non-monotonic advance timestamps do not produce NaN or negative fraction', () {
      final h = history()..reset(Duration.zero);
      h.record(loud, Duration.zero);
      h.advance(interval * settledColumns);
      h.advance(interval);

      expect(h.live.isFinite, isTrue);
      expect(h.fraction, greaterThanOrEqualTo(0));
    });
  });
}
