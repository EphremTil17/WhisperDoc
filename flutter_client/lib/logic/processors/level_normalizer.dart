import 'dart:math' as math;

/// Maps raw microphone amplitude onto a 0–1 display level that adapts to the
/// input, so a quiet laptop mic and a hot USB headset both fill the meter.
///
/// Works in decibels. A noise floor follows the quietest recent input (falls
/// fast, rises slowly) and a peak envelope follows the loudest (jumps up
/// instantly, decays slowly). The output is the input's position between the
/// two. Sound within [noiseMarginDb] of the floor reads as zero, and the range
/// never shrinks below [minRangeDb], so room noise is not stretched to full
/// scale.
///
/// Time constants are applied against the real time between samples, so the
/// behaviour does not depend on how often the recorder delivers chunks.
class LevelNormalizer {
  LevelNormalizer({
    this.noiseMarginDb = _defaultNoiseMarginDb,
    this.minRangeDb = _defaultMinRangeDb,
    this.floorFall = const Duration(milliseconds: 200),
    this.floorRise = const Duration(seconds: 4),
    this.peakRelease = const Duration(seconds: 3),
  });

  static const double _defaultNoiseMarginDb = 6;
  static const double _defaultMinRangeDb = 12;

  /// Amplitude ratio to decibels: dB = 20 · log10(ratio).
  static const double _decibelsPerDecade = 20;
  static const double _silenceDb = -100;
  static const double _initialFloorDb = -60;
  static const double _initialPeakDb = -20;

  /// Headroom above the noise floor that still reads as silence.
  final double noiseMarginDb;

  /// Smallest span between the silence threshold and full scale.
  final double minRangeDb;

  /// How quickly the floor drops to a quieter input.
  final Duration floorFall;

  /// How slowly the floor creeps up under sustained sound (so speech is not
  /// mistaken for noise).
  final Duration floorRise;

  /// How slowly the peak relaxes after loud input (the auto-gain speed).
  final Duration peakRelease;

  double _floorDb = _initialFloorDb;
  double _peakDb = _initialPeakDb;
  Duration? _lastSampleAt;

  /// Forgets everything learned about the input, e.g. when the device changes.
  void reset() {
    _floorDb = _initialFloorDb;
    _peakDb = _initialPeakDb;
    _lastSampleAt = null;
  }

  /// Returns the display level (0–1) for [raw], a linear amplitude in 0–1
  /// (mean absolute PCM sample over full scale) captured at [at].
  ///
  /// A raw value of exactly zero is the recorder's reset signal, not a
  /// measurement, so it returns zero without disturbing the learned range.
  double normalize(double raw, Duration at) {
    if (raw <= 0) return 0;

    final db = math.max(
      _silenceDb,
      math.log(raw) / math.ln10 * _decibelsPerDecade,
    );
    final previous = _lastSampleAt;
    final elapsed = previous == null ? Duration.zero : at - previous;
    _lastSampleAt = at;

    _floorDb = _follow(
      _floorDb,
      db,
      db < _floorDb ? floorFall : floorRise,
      elapsed,
    );
    _peakDb = db > _peakDb ? db : _follow(_peakDb, db, peakRelease, elapsed);

    final low = _floorDb + noiseMarginDb;
    final high = math.max(_peakDb, low + minRangeDb);

    return ((db - low) / (high - low)).clamp(0.0, 1.0);
  }

  /// Moves [current] toward [target] as a one-pole filter with time constant
  /// [tau] over [elapsed].
  static double _follow(
    double current,
    double target,
    Duration tau,
    Duration elapsed,
  ) {
    if (elapsed <= Duration.zero) return current;
    final k = 1 - math.exp(-elapsed.inMicroseconds / tau.inMicroseconds);

    return current + (target - current) * k;
  }
}
