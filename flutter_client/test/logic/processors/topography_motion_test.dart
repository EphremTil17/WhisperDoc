import 'package:flutter_client/logic/processors/topography_motion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const frame = 1 / 60;
  const half = 0.5;
  const tolerance = 0.01;
  const x = 120.0;
  const y = 300.0;
  const moved = 40.0;
  const longGap = 10.0;
  const idleFrame = 0.066;

  /// Advances [m] by [seconds] in display frames.
  void run(TopographyMotion m, double seconds, {double step = frame}) {
    for (var t = 0.0; t < seconds; t += step) {
      m.advance(step);
    }
  }

  group('TopographyMotion', () {
    test('rises from flat ground, fast first, to the full relief', () {
      final m = TopographyMotion();
      expect(m.rise, 0);
      expect(m.animating, isTrue);

      run(m, TopographyMotion.riseSeconds * half);
      expect(m.rise, greaterThan(half));
      expect(m.interacting, isTrue, reason: 'rising takes full frame rate');

      run(m, TopographyMotion.riseSeconds);
      expect(m.rise, 1);
      expect(m.interacting, isFalse, reason: 'only the drift is left');
    });

    test('flattens quickly for a recording, then needs no frames', () {
      final m = TopographyMotion();
      run(m, TopographyMotion.riseSeconds);
      m.active = false;
      expect(m.asleep, isFalse);

      run(m, TopographyMotion.fallSeconds + frame);
      expect(m.rise, 0);
      expect(m.asleep, isTrue);
      expect(m.animating, isFalse);
    });

    test('the peak rises where the cursor enters and follows it', () {
      final m = TopographyMotion();
      run(m, TopographyMotion.riseSeconds);
      m.hover(x, y);
      expect(m.peakX, x);
      expect(m.interacting, isTrue);

      m.hover(x + moved, y);
      run(m, 1);
      expect(m.peakX, closeTo(x + moved, half));
      expect(m.peakHeight, closeTo(1, tolerance));
      expect(m.interacting, isFalse, reason: 'the peak has caught up');

      m.leave();
      run(m, 1);
      expect(m.peakHeight, closeTo(0, tolerance));
    });

    test('the spring settles the same at any frame length', () {
      final fine = TopographyMotion()..hover(x, y);
      final coarse = TopographyMotion()..hover(x, y);
      fine.hover(x + moved, y);
      coarse.hover(x + moved, y);
      run(fine, 1);
      run(coarse, 1, step: idleFrame);

      expect(coarse.peakX, closeTo(fine.peakX, half));
    });

    test('a click wave travels for its lifetime, then is gone', () {
      final m = TopographyMotion();
      run(m, TopographyMotion.riseSeconds);
      m.tap(x, y);
      expect(m.waveStrength, 1);
      expect(m.interacting, isTrue);

      run(m, TopographyMotion.waveSeconds + frame);
      expect(m.waveStrength, 0);
      expect(m.interacting, isFalse);
    });

    test('settling without frames flattens for a recording', () {
      // A recording started from another app: frames have stopped, so the
      // relief must reach flat ground now rather than stay drawn.
      final m = TopographyMotion();
      run(m, TopographyMotion.riseSeconds);
      m
        ..active = false
        ..settle();
      expect(m.rise, 0);
      expect(m.asleep, isTrue);

      m
        ..active = true
        ..settle();
      expect(m.rise, 1, reason: 'the map is whole again afterwards');
    });

    test('settling ends a wave and lands the peak on its target', () {
      final m = TopographyMotion();
      run(m, TopographyMotion.riseSeconds);
      m
        ..hover(x, y)
        ..hover(x + moved, y)
        ..tap(x, y)
        ..settle();

      expect(m.waveStrength, 0);
      expect(m.peakX, x + moved);
      expect(m.peakHeight, 1);
      expect(m.interacting, isFalse);
    });

    test('a long gap resumes instead of jumping', () {
      final m = TopographyMotion()..advance(longGap);

      expect(m.time, lessThan(frame * moved));
      expect(m.rise, lessThan(1));
    });

    test('a still map is drawn whole and needs no frames', () {
      final m = TopographyMotion()..still = true;
      expect(m.rise, 1);
      expect(m.animating, isFalse);
      expect(m.interacting, isFalse);

      m
        ..hover(x, y)
        ..tap(x, y)
        ..advance(1);
      expect(m.time, 0);
      expect(m.peakHeight, 0);
      expect(m.waveStrength, 0);

      m.active = false;
      expect(m.asleep, isTrue);
    });

    test('negative or zero dt is ignored', () {
      final m = TopographyMotion()
        ..advance(0)
        ..advance(-frame);

      expect(m.time, 0);
      expect(m.rise, 0);
    });

    test('a second click replaces an in-flight wave at the new origin', () {
      final m = TopographyMotion();
      run(m, TopographyMotion.riseSeconds);
      m.tap(x, y);
      run(m, half);
      expect(m.waveAge, greaterThan(0));

      m.tap(x + moved, y + moved);
      expect(m.waveAge, 0);
      expect(m.waveX, x + moved);
      expect(m.waveY, y + moved);
      expect(m.waveStrength, 1);
    });

    test('toggling still off resumes drift cleanly from full relief', () {
      final m = TopographyMotion()..still = true;
      expect(m.rise, 1);

      m
        ..still = false
        ..advance(frame);
      expect(m.animating, isTrue);
      expect(m.time, closeTo(frame, tolerance));
    });
  });
}
