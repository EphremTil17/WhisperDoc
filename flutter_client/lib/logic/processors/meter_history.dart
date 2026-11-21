import 'dart:math' as math;
import 'dart:typed_data';

/// Time-based model behind the pixel meter: a fixed ring of column levels,
/// the scroll position between columns, an eased live level and a peak hold.
///
/// Columns advance at a fixed rate ([columnInterval]) independent of how
/// often audio levels arrive or frames render, so the strip moves at a steady
/// speed on any display. Nothing here allocates after construction.
class MeterHistory {
  MeterHistory({
    this.capacity = _defaultCapacity,
    this.columnInterval = const Duration(milliseconds: 50),
    this.liveEase = const Duration(milliseconds: 40),
    this.peakHold = const Duration(milliseconds: 450),
    this.peakFallPerSecond = _defaultPeakFall,
  }) : _levels = Float32List(capacity);

  static const int _defaultCapacity = 64;
  static const double _defaultPeakFall = 2.0;
  static const int _microsPerSecond = 1000000;

  /// Columns kept; must cover the widest strip that will be drawn.
  final int capacity;
  final Duration columnInterval;

  /// Time constant for the live column chasing the latest level.
  final Duration liveEase;
  final Duration peakHold;

  /// How fast the peak marker falls once the hold expires (levels/second).
  final double peakFallPerSecond;

  final Float32List _levels;
  int _head = 0;
  Duration _lastColumnAt = Duration.zero;
  Duration _lastFrameAt = Duration.zero;
  Duration _peakSetAt = Duration.zero;
  double _target = 0;
  double _live = 0;
  double _peak = 0;
  double _fraction = 0;

  /// Latest normalised level (0–1); the next column records it.
  set level(double value) => _target = value;

  /// Eased level of the newest, still-growing column.
  double get live => _live;

  /// Peak-hold level (0–1).
  double get peak => _peak;

  /// Progress (0–1) from the newest column toward the next one, for smooth
  /// scrolling between column steps.
  double get fraction => _fraction;

  /// Level of the column [age] steps old (0 is the newest settled column).
  double columnAt(int age) => _levels[(_head - age) % capacity];

  /// Clears history, e.g. when a new recording starts at [now].
  void reset(Duration now) {
    _levels.fillRange(0, capacity, 0);
    _head = 0;
    _lastColumnAt = now;
    _lastFrameAt = now;
    _peakSetAt = now;
    _target = 0;
    _live = 0;
    _peak = 0;
    _fraction = 0;
  }

  /// Advances to [now]: settles any due columns and updates the live level,
  /// peak and scroll fraction.
  void advance(Duration now) {
    final frame = now - _lastFrameAt;
    _lastFrameAt = now;

    final step = columnInterval.inMicroseconds;
    while ((now - _lastColumnAt).inMicroseconds >= step) {
      _lastColumnAt += columnInterval;
      _head = (_head + 1) % capacity;
      _levels[_head] = _target;
    }
    _fraction = (now - _lastColumnAt).inMicroseconds / step;

    final ease = 1 - math.exp(-frame.inMicroseconds / liveEase.inMicroseconds);
    _live += (_target - _live) * ease;

    final shown = math.max(_live, _levels[_head]);
    if (shown >= _peak) {
      _peak = shown;
      _peakSetAt = now;
    } else if (now - _peakSetAt > peakHold) {
      final fall = peakFallPerSecond * frame.inMicroseconds / _microsPerSecond;
      _peak = math.max(shown, _peak - fall);
    }
  }
}
