import 'dart:math' as math;

/// The moving parts behind the contour background, kept out of the widget so
/// they can be tested: the drift clock, the relief rising from flat ground
/// (and collapsing for a recording), the cursor peak on a spring, and the
/// wave a click sends out.
///
/// [animating] tells the driver whether frames are needed at all, and
/// [interacting] whether they should come at the display's full rate (more
/// than the slow drift is moving); [asleep] whether there is anything to
/// draw.
class TopographyMotion {
  /// Seconds for the relief to rise from flat ground (eased out).
  static const double riseSeconds = 1.8;

  /// Seconds to flatten when a recording starts: quick, so the meter leads.
  static const double fallSeconds = 0.25;

  /// Seconds a click wave travels before it is gone.
  static const double waveSeconds = 2.6;

  /// The peak follows the cursor on this spring (unit mass).
  static const double stiffness = 120;
  static const double damping = 20;

  /// Longest step simulated at once: longer than an idle drift frame, so the
  /// drift keeps its speed, while a real pause (window unfocused, panel
  /// open) resumes rather than jumping.
  static const double _maxStep = 0.1;
  static const double _springStep = 1 / 240;

  static const double _hidden = 0.01;

  /// The spring counts as at rest within these.
  static const double _restDistance = 0.5;
  static const double _restSpeed = 1;
  static const double _restHeight = 0.002;

  bool _active = true;
  bool _still = false;
  double _rising = 0;
  double _time = 0;

  double _peakX = 0;
  double _peakY = 0;
  double _peakZ = 0;
  double _velX = 0;
  double _velY = 0;
  double _velZ = 0;
  double _targetX = 0;
  double _targetY = 0;
  double _targetZ = 0;

  double _waveX = 0;
  double _waveY = 0;
  double _waveAge = waveSeconds;

  /// Drift clock in seconds; stands still under reduced motion.
  double get time => _time;

  /// 0 is flat ground, 1 the full relief (cubic ease-out; multiplied out,
  /// since this is read every frame).
  double get rise {
    final left = 1 - _rising;

    return 1 - left * left * left;
  }

  double get peakX => _peakX;
  double get peakY => _peakY;
  double get peakHeight => _peakZ;

  double get waveX => _waveX;
  double get waveY => _waveY;
  double get waveAge => _waveAge;

  /// 1 while a wave is travelling, else 0.
  double get waveStrength => _waveAge < waveSeconds ? 1 : 0;

  /// Flat and staying flat: nothing to draw or animate.
  bool get asleep => !_active && _rising == 0;

  /// Frames are needed: the relief is up (or moving) and not a still map.
  bool get animating => !_still && !asleep;

  /// More than the drift is moving: the relief rising or falling, a wave
  /// travelling, or the peak on its way to the cursor.
  bool get interacting =>
      animating &&
      (_rising != (_active ? 1 : 0) ||
          _waveAge < waveSeconds ||
          (_peakX - _targetX).abs() >= _restDistance ||
          (_peakY - _targetY).abs() >= _restDistance ||
          (_peakZ - _targetZ).abs() >= _restHeight ||
          _velX.abs() >= _restSpeed ||
          _velY.abs() >= _restSpeed ||
          _velZ.abs() >= _restHeight);

  /// Raises the relief (true) or flattens it (false).
  set active(bool value) {
    _active = value;
    if (_still) _rising = value ? 1 : 0;
  }

  /// Reduced motion: a still map, no drift, peak or wave.
  set still(bool value) {
    _still = value;
    if (!value) return;
    _rising = _active ? 1 : 0;
    _peakZ = _targetZ = _velZ = 0;
    _waveAge = waveSeconds;
  }

  /// Frames have stopped (the window lost focus): jump to where everything
  /// was heading. A recording started from another app then leaves no
  /// contours behind the meter, so the shader is not re-run on every meter
  /// frame, and the map is whole again afterwards without frames to rise.
  void settle() {
    _rising = _active ? 1 : 0;
    _peakX = _targetX;
    _peakY = _targetY;
    _peakZ = _targetZ;
    _velX = _velY = _velZ = 0;
    _waveAge = waveSeconds;
  }

  /// The cursor is at ([x], [y]): the peak rises there and follows.
  void hover(double x, double y) {
    if (_still) return;
    // Rise where the cursor came in rather than sliding over from the last
    // place it left.
    if (_peakZ < _hidden) {
      _peakX = x;
      _peakY = y;
      _velX = _velY = 0;
    }
    _targetX = x;
    _targetY = y;
    _targetZ = 1;
  }

  /// The cursor left: the peak sinks back.
  void leave() => _targetZ = 0;

  /// A click at ([x], [y]) sends out a wave, replacing any still travelling.
  void tap(double x, double y) {
    if (_still) return;
    _waveX = x;
    _waveY = y;
    _waveAge = 0;
  }

  /// Advances everything by [seconds] of real time.
  void advance(double seconds) {
    if (_still || seconds <= 0) return;
    final dt = math.min(seconds, _maxStep);

    _time += dt;
    _rising = _active
        ? math.min(1, _rising + dt / riseSeconds)
        : math.max(0, _rising - dt / fallSeconds);
    _waveAge = math.min(waveSeconds, _waveAge + dt);

    // Small sub-steps keep the spring stable however long the frame was.
    for (var left = dt; left > 0; left -= _springStep) {
      _springStepBy(math.min(left, _springStep));
    }
  }

  void _springStepBy(double dt) {
    _velX += (stiffness * (_targetX - _peakX) - damping * _velX) * dt;
    _velY += (stiffness * (_targetY - _peakY) - damping * _velY) * dt;
    _velZ += (stiffness * (_targetZ - _peakZ) - damping * _velZ) * dt;
    _peakX += _velX * dt;
    _peakY += _velY * dt;
    _peakZ += _velZ * dt;
  }
}
