import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/processors/level_normalizer.dart';
import 'package:flutter_client/logic/processors/meter_history.dart';

/// The recording meter: retro pixel blocks scrolling at display refresh.
///
/// A vsync [Ticker] advances [MeterHistory] each frame and repaints the
/// painter through a listenable, so no widget rebuilds while it runs. Raw
/// microphone amplitude from [levels] is mapped through [normalizer], which
/// the parent owns so the learned range survives between recordings.
class PixelMeter extends StatefulWidget {
  const PixelMeter({
    super.key,
    required this.levels,
    required this.normalizer,
  });

  final Stream<double> levels;
  final LevelNormalizer normalizer;

  @override
  State<PixelMeter> createState() => _PixelMeterState();
}

class _PixelMeterState extends State<PixelMeter>
    with SingleTickerProviderStateMixin {
  final MeterHistory _history = MeterHistory();
  final Stopwatch _clock = Stopwatch()..start();
  final _MeterFrame _frame = _MeterFrame();
  Ticker? _ticker;
  StreamSubscription<double>? _subscription;

  @override
  void initState() {
    super.initState();
    _history.reset(Duration.zero);
    _subscription = widget.levels.listen(_onLevel);
    final ticker = createTicker(_onTick);
    _ticker = ticker;
    unawaited(ticker.start());
  }

  @override
  void didUpdateWidget(PixelMeter old) {
    super.didUpdateWidget(old);
    if (old.levels != widget.levels) {
      unawaited(_subscription?.cancel());
      _subscription = widget.levels.listen(_onLevel);
    }
  }

  /// Levels keep arriving while a panel covers the meter and mutes the
  /// ticker, so the history is recorded here, on one clock with the frames.
  void _onLevel(double raw) {
    final now = _clock.elapsed;
    _history.record(widget.normalizer.normalize(raw, now), now);
  }

  void _onTick(Duration _) {
    _history.advance(_clock.elapsed);
    _frame.tick();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    unawaited(_subscription?.cancel());
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _PixelMeterPainter(
          history: _history,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          repaint: _frame,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Fires once per ticker frame to repaint without rebuilding.
class _MeterFrame extends ChangeNotifier {
  void tick() => notifyListeners();
}

/// Draws the meter as square points, one draw call per colour tier, from
/// preallocated buffers (no per-frame allocation beyond list views).
class _PixelMeterPainter extends CustomPainter {
  _PixelMeterPainter({
    required this.history,
    required this.devicePixelRatio,
    required Listenable repaint,
  }) : super(repaint: repaint);

  static const double _cell = 6;
  static const double _pitch = 8;
  static const double _half = 2;

  /// Columns younger than these ages use the bright, then mid tier.
  static const double _brightAge = 10;
  static const double _midAge = 26;

  final MeterHistory history;
  final double devicePixelRatio;

  static final _Tier _tip = _Tier(AppMeterColors.tip);
  static final _Tier _bright = _Tier(AppMeterColors.bright);
  static final _Tier _mid = _Tier(AppMeterColors.mid);
  static final _Tier _dim = _Tier(AppMeterColors.dim);
  static final _Tier _peak = _Tier(AppMeterColors.peak);
  static final List<_Tier> _tiers = [_dim, _mid, _bright, _tip, _peak];

  double _snap(double v) =>
      (v * devicePixelRatio).roundToDouble() / devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final rows = (size.height / _half / _pitch).floor();
    if (rows < 1) return;
    final columns = (size.width / _pitch).ceil() + 1;
    for (final tier in _tiers) {
      tier.reset(columns * rows * _half.toInt());
    }

    final centre = _snap(size.height / _half);
    final peakRows = _rowsFor(history.peak, rows);

    for (var age = 0; age < columns; age++) {
      final position = age + history.fraction;
      final x = _snap(size.width - _cell - position * _pitch);
      if (x < -_cell) break;

      // The newest column is still growing: show its eased live level.
      final level = age == 0
          ? math.max(history.live, history.columnAt(0))
          : history.columnAt(age);
      final n = _rowsFor(level, rows);
      final body = _tierFor(position);

      for (var r = 0; r < n; r++) {
        // The light tip caps a column of sound; a one-row silent column
        // stays in its body colour so silence never reads brighter.
        final isTip = n > 1 && r == n - 1 && position < _brightAge;
        final tier = isTip ? _tip : body;
        tier.addPair(x, centre, r);
      }
      if (age == 0 && peakRows > n) _peak.addPair(x, centre, peakRows - 1);
    }

    for (final tier in _tiers) {
      tier.draw(canvas);
    }
  }

  /// Colour steps darker as a column ages: bright, then mid, then dim.
  static _Tier _tierFor(double age) {
    if (age < _brightAge) return _bright;
    if (age < _midAge) return _mid;

    return _dim;
  }

  static int _rowsFor(double level, int rows) =>
      (level * rows).round().clamp(1, rows);

  @override
  bool shouldRepaint(_PixelMeterPainter old) =>
      old.devicePixelRatio != devicePixelRatio || old.history != history;
}

/// One colour tier: a reusable point buffer drawn as squares.
class _Tier {
  _Tier(Color color)
    : _paint = Paint()
        ..color = color
        ..strokeWidth = _PixelMeterPainter._cell
        ..strokeCap = StrokeCap.square;

  final Paint _paint;
  Float32List _points = Float32List(0);
  int _count = 0;

  void reset(int maxCells) {
    final needed = maxCells * _PixelMeterPainter._half.toInt();
    if (_points.length < needed) _points = Float32List(needed);
    _count = 0;
  }

  /// Adds the mirrored cell pair [row] steps out from [centre] at column [x].
  void addPair(double x, double centre, int row) {
    const half = _PixelMeterPainter._cell / _PixelMeterPainter._half;
    final cx = x + half;
    final offset = row * _PixelMeterPainter._pitch + 1 + half;
    _points
      ..[_count++] = cx
      ..[_count++] = centre - offset
      ..[_count++] = cx
      ..[_count++] = centre + offset;
  }

  void draw(Canvas canvas) {
    if (_count == 0) return;
    canvas.drawRawPoints(
      ui.PointMode.points,
      Float32List.sublistView(_points, 0, _count),
      _paint,
    );
  }
}
