import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/processors/topography_motion.dart';
import 'package:flutter_client/services/utility/logging_service.dart';

/// Contour lines behind [child], drawn on the GPU (shaders/topography.frag):
/// a slowly drifting relief, a peak that follows the cursor, a wave where you
/// click, fading out toward every edge. While [active] is false the relief
/// flattens and stops; while [moving] is false (the setting, or reduced
/// motion) it is a still map drawn once.
///
/// Frames follow the display (every vsync, the monitor's native rate) while
/// more than the drift moves: the cursor peak, a click wave, the rise. The
/// slow drift alone is paced by a timer at about 60 frames a second
/// ([_driftGap]), since a frame redraws the whole window and the drift gains
/// nothing from 240. Nothing runs while flat or still, while the window is
/// not focused, or while a panel covers it (its ticker is muted).
class TopographyBackground extends StatefulWidget {
  const TopographyBackground({
    super.key,
    required this.active,
    required this.moving,
    required this.child,
  });

  final bool active;
  final bool moving;
  final Widget child;

  /// Begins loading the GLSL fragment program early (e.g. during boot) so the
  /// first home-screen frame does not wait on asset IO.
  static void preload() => unawaited(_TopographyBackgroundState._program);

  @override
  State<TopographyBackground> createState() => _TopographyBackgroundState();
}

class _TopographyBackgroundState extends State<TopographyBackground>
    with SingleTickerProviderStateMixin {
  /// Wait after a drift-only frame before asking for the next vsync: under
  /// one frame of 60, so the drift never falls below 60 frames a second.
  static const Duration _driftGap = Duration(milliseconds: 12);
  static const double _microsPerSecond = 1e6;

  /// Loaded once for the app's lifetime.
  static final Future<ui.FragmentProgram?> _program = _load();

  final TopographyMotion _motion = TopographyMotion();
  final _Frame _frame = _Frame();
  final Stopwatch _clock = Stopwatch()..start();
  int _lastMicros = 0;
  Ticker? _ticker;
  Timer? _nextFrame;
  AppLifecycleListener? _lifecycle;
  ui.FragmentShader? _shader;
  bool _focused = true;
  bool _ticking = true;
  bool? _lastStill;

  static Future<ui.FragmentProgram?> _load() async {
    try {
      return await ui.FragmentProgram.fromAsset('shaders/topography.frag');
    } catch (e) {
      // Without shaders the ground stays plain; nothing else depends on it.
      LoggingService().warning('Topography shader unavailable: $e');

      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
    _focused = _isFocused(WidgetsBinding.instance.lifecycleState);
    _motion.active = widget.active;
    _ticker = createTicker(_onTick);
    unawaited(_attachShader());
  }

  Future<void> _attachShader() async {
    final program = await _program;
    if (!mounted || program == null) return;
    setState(() => _shader = program.fragmentShader());
    _run();
  }

  static bool _isFocused(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed;

  void _onLifecycle(AppLifecycleState state) {
    final focused = _isFocused(state);
    if (focused == _focused) return;
    _focused = focused;
    _run();
  }

  @override
  void didUpdateWidget(TopographyBackground old) {
    super.didUpdateWidget(old);
    final still = _still;
    if (old.active == widget.active && _lastStill == still) return;
    _lastStill = still;
    _motion
      ..active = widget.active
      ..still = still;
    _run();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A panel covering the home screen mutes the ticker without any
    // lifecycle change, so [_run] never sees the pause. Restart the frame
    // clock when ticking is re-enabled, or the first frame after the panel
    // closes would advance by the whole time it was open.
    final ticking = TickerMode.valuesOf(context).enabled;
    if (ticking && !_ticking) _lastMicros = _clock.elapsedMicroseconds;
    _ticking = ticking;
    final still = _still;
    if (_lastStill == still) return;
    _lastStill = still;
    _motion.still = still;
    _run();
  }

  bool get _still => !widget.moving || MediaQuery.disableAnimationsOf(context);

  /// Starts frames if anything should move, or repaints once if nothing will.
  ///
  /// Reached on every pointer move (up to 1000 a second), so it never touches
  /// the frame clock; a waiting drift frame is dropped so the response to
  /// the cursor starts on the very next vsync.
  void _run() {
    final ticker = _ticker;
    if (ticker == null || _shader == null) return;
    if (!_motion.animating || !_focused) {
      _nextFrame?.cancel();
      _nextFrame = null;
      ticker.stop();
      if (!_focused) _motion.settle();
      _frame.tick();

      return;
    }
    if (ticker.isActive) return;
    final wasStopped = _nextFrame == null;
    _nextFrame?.cancel();
    _nextFrame = null;
    // Reset the frame clock when resuming from a pause (unfocused, minimized,
    // panel-covered, or flat) so the first frame advances smoothly instead of
    // jumping by the full _maxStep clamp.
    if (wasStopped) _lastMicros = _clock.elapsedMicroseconds;
    unawaited(ticker.start());
  }

  /// While interacting the ticker keeps running, a frame every vsync; for
  /// the drift alone it stops after each frame and a timer brings the next.
  void _onTick(Duration _) {
    // Plain integers: a frame allocates nothing here.
    final now = _clock.elapsedMicroseconds;
    _motion.advance((now - _lastMicros) / _microsPerSecond);
    _lastMicros = now;
    _frame.tick();

    if (_motion.interacting && _focused) return;
    _ticker?.stop();
    if (_motion.animating && _focused) _nextFrame = Timer(_driftGap, _wake);
  }

  void _wake() {
    _nextFrame = null;
    final ticker = _ticker;
    if (mounted && ticker != null && !ticker.isActive) {
      unawaited(ticker.start());
    }
  }

  /// Pointer input only ever starts frames; a still or paused map ignores it
  /// (Windows sends moves to unfocused windows too).
  void _kick() {
    if (_motion.animating && _focused) _run();
  }

  void _hover(PointerHoverEvent event) {
    _motion.hover(event.localPosition.dx, event.localPosition.dy);
    _kick();
  }

  void _leave(PointerExitEvent _) {
    _motion.leave();
    _kick();
  }

  void _tap(PointerDownEvent event) {
    _motion.tap(event.localPosition.dx, event.localPosition.dy);
    _kick();
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _nextFrame?.cancel();
    _ticker?.dispose();
    _shader?.dispose();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;

    return MouseRegion(
      onExit: _leave,
      child: Listener(
        onPointerHover: _hover,
        onPointerDown: _tap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (shader != null)
              RepaintBoundary(
                child: CustomPaint(
                  painter: _TopographyPainter(
                    shader: shader,
                    motion: _motion,
                    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                    repaint: _frame,
                  ),
                ),
              ),
            widget.child,
          ],
        ),
      ),
    );
  }
}

/// Repaints the painter without rebuilding.
class _Frame extends ChangeNotifier {
  void tick() => notifyListeners();
}

class _TopographyPainter extends CustomPainter {
  _TopographyPainter({
    required this.shader,
    required this.motion,
    required this.devicePixelRatio,
    required Listenable repaint,
  }) : _paint = Paint()..shader = shader,
       super(repaint: repaint);

  /// Contour lines per unit of relief height.
  static const double _levels = 11;

  /// Logical pixels per hill.
  static const double _scale = 190;

  static const double _oct0Vx = 0.05;
  static const double _oct0Vy = -0.035;
  static const double _oct1Vx = -0.03;
  static const double _oct1Vy = 0.045;
  static const double _oct1Offset = 7.3;
  static const double _oct2Vy = 0.025;
  static const double _oct2Offset = -3.1;

  final ui.FragmentShader shader;
  final TopographyMotion motion;
  final double devicePixelRatio;

  /// Made once per painter, not per frame.
  final Paint _paint;

  /// Runs every frame, so it allocates nothing: uniforms are written straight
  /// into the shader in declaration order (see topography.frag).
  ///
  /// Each octave's drift is split in float64 into its integer cell and [0, 1)
  /// fractional part so float32 uniforms never lose sub-pixel smoothness even
  /// after days of continuous drift.
  @override
  void paint(Canvas canvas, Size size) {
    final rise = motion.rise;
    if (rise <= 0) return;
    const ink = AppColors.textMuted;
    final t = motion.time;
    final d0x = _oct0Vx * t;
    final d0y = _oct0Vy * t;
    final d1x = _oct1Vx * t + _oct1Offset;
    final d1y = _oct1Vy * t + _oct1Offset;
    const d2x = _oct2Offset;
    final d2y = _oct2Vy * t + _oct2Offset;
    final d0xI = d0x.floorToDouble();
    final d0yI = d0y.floorToDouble();
    final d1xI = d1x.floorToDouble();
    final d1yI = d1y.floorToDouble();
    final d2xI = d2x.floorToDouble();
    final d2yI = d2y.floorToDouble();
    var i = 0;
    shader
      ..setFloat(i++, size.width)
      ..setFloat(i++, size.height)
      ..setFloat(i++, devicePixelRatio)
      ..setFloat(i++, d0x - d0xI)
      ..setFloat(i++, d0y - d0yI)
      ..setFloat(i++, d0xI)
      ..setFloat(i++, d0yI)
      ..setFloat(i++, d1x - d1xI)
      ..setFloat(i++, d1y - d1yI)
      ..setFloat(i++, d1xI)
      ..setFloat(i++, d1yI)
      ..setFloat(i++, d2x - d2xI)
      ..setFloat(i++, d2y - d2yI)
      ..setFloat(i++, d2xI)
      ..setFloat(i++, d2yI)
      ..setFloat(i++, rise)
      ..setFloat(i++, _levels)
      ..setFloat(i++, _scale)
      ..setFloat(i++, motion.peakX)
      ..setFloat(i++, motion.peakY)
      ..setFloat(i++, motion.peakHeight)
      ..setFloat(i++, motion.waveX)
      ..setFloat(i++, motion.waveY)
      ..setFloat(i++, motion.waveAge)
      ..setFloat(i++, motion.waveStrength)
      ..setFloat(i++, ink.r)
      ..setFloat(i++, ink.g)
      ..setFloat(i, ink.b);
    canvas.drawRect(Offset.zero & size, _paint);
  }

  @override
  bool shouldRepaint(_TopographyPainter old) =>
      old.shader != shader || old.devicePixelRatio != devicePixelRatio;
}
