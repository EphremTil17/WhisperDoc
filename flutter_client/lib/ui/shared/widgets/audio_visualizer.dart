import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/services/hardware/audio_service.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';

/// Configuration for the waveform visualizer (easily adjustable)
class WaveformConfig {
  static const int sampleCount = 50;
  static const int fadeBarCount = 10;
  static const double barWidth = 2.0;
  static const double barGap = 2.0;
  static const double minBarHeight = 3.0;
  static const double maxBarHeightRatio = 0.9;
  static const double gainMultiplier = 500.0; // Reduce for less sensitivity
  static const int throttleMs =
      16; // 60fps - smooth without excessive CPU (20 for 5fps, 16 for 60fps)
  static const double invisibleThreshold = 0.05; // Skip bars below this opacity
  static const double glowThreshold = 0.15; // Min amplitude for glow effect
}

/// High-performance scrolling waveform visualizer
///
/// Optimizations:
/// - O(1) circular buffer (no array shifting)
/// - Throttled setState (max 20fps)
/// - Pre-allocated Paint objects
/// - Early skip for invisible bars
/// - RepaintBoundary isolation
class AudioVisualizer extends StatefulWidget {
  const AudioVisualizer({super.key});

  @override
  State<AudioVisualizer> createState() => _AudioVisualizerState();
}

class _AudioVisualizerState extends State<AudioVisualizer> {
  // Circular buffer for O(1) insertion
  final List<double> _buffer = List.filled(WaveformConfig.sampleCount, 0.0);
  int _writeIndex = 0;
  int _version = 0;

  // Throttling
  Timer? _throttleTimer;
  double _pendingAmplitude = 0.0;
  bool _hasPendingUpdate = false;

  StreamSubscription<double>? _subscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setupSubscription();
  }

  void _setupSubscription() {
    unawaited(_subscription?.cancel());
    final audioService = context.read<AudioService>();
    _subscription = audioService.amplitudeStream.listen(_onAmplitude);
  }

  void _onAmplitude(double rawAmplitude) {
    // Logarithmic scaling with configurable gain
    _pendingAmplitude = rawAmplitude > 0.0001
        ? (math.log(rawAmplitude * WaveformConfig.gainMultiplier + 1) /
                  math.log(11))
              .clamp(0.0, 1.0)
        : 0.0;
    _hasPendingUpdate = true;

    // Throttle updates to reduce setState calls
    _throttleTimer ??= Timer(
      const Duration(milliseconds: WaveformConfig.throttleMs),
      _flushUpdate,
    );
  }

  void _flushUpdate() {
    _throttleTimer = null;
    if (!_hasPendingUpdate || !mounted) return;

    setState(() {
      // O(1) circular buffer write
      _buffer[_writeIndex] = _pendingAmplitude;
      _writeIndex = (_writeIndex + 1) % WaveformConfig.sampleCount;
      _version++;
      _hasPendingUpdate = false;
    });
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audioService = context.watch<AudioService>();

    return RepaintBoundary(
      child: SizedBox(
        height: 40,
        width: 220,
        child: CustomPaint(
          painter: _WaveformPainter(
            buffer: _buffer,
            writeIndex: _writeIndex,
            version: _version,
            color: AppTheme.crimsonPrimary,
            isActive: audioService.isRecording,
          ),
        ),
      ),
    );
  }
}

/// Optimized CustomPainter with pre-allocated resources
class _WaveformPainter extends CustomPainter {
  final List<double> buffer;
  final int writeIndex;
  final int version;
  final Color color;
  final bool isActive;

  // Pre-allocated Paint objects (reused each frame)
  static final Paint _barPaint = Paint()
    ..strokeCap = StrokeCap.round
    ..strokeWidth = WaveformConfig.barWidth;

  static final Paint _glowPaint = Paint()
    ..strokeCap = StrokeCap.round
    ..strokeWidth = WaveformConfig.barWidth + 2
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

  _WaveformPainter({
    required this.buffer,
    required this.writeIndex,
    required this.version,
    required this.color,
    required this.isActive,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (buffer.isEmpty) return;

    const totalBarWidth = WaveformConfig.barWidth + WaveformConfig.barGap;
    final centerY = size.height / 2;
    final maxBarHeight = size.height * WaveformConfig.maxBarHeightRatio;

    const totalWidth = WaveformConfig.sampleCount * totalBarWidth;
    final startX = (size.width - totalWidth) / 2;

    for (int i = 0; i < WaveformConfig.sampleCount; i++) {
      // Calculate edge fade first (early skip optimization)
      double edgeFade = 1.0;
      if (i < WaveformConfig.fadeBarCount) {
        final t = i / WaveformConfig.fadeBarCount;
        edgeFade = t * t; // Quadratic easing
      } else if (i >
          WaveformConfig.sampleCount - WaveformConfig.fadeBarCount - 1) {
        final t =
            (WaveformConfig.sampleCount - 1 - i) / WaveformConfig.fadeBarCount;
        edgeFade = t * t;
      }

      // Early skip for invisible bars (saves all subsequent calculations)
      final baseOpacity = isActive ? 1.0 : 0.3;
      final barOpacity = baseOpacity * edgeFade;
      if (barOpacity < WaveformConfig.invisibleThreshold) continue;

      // Read from circular buffer in correct display order
      final bufferIndex = (writeIndex + i) % WaveformConfig.sampleCount;
      final amplitude = buffer[bufferIndex];

      final barHeight =
          WaveformConfig.minBarHeight +
          (amplitude * (maxBarHeight - WaveformConfig.minBarHeight));
      final x = startX + (i * totalBarWidth);
      final halfHeight = barHeight / 2;

      // Glow effect for visible bars with sufficient amplitude
      if (amplitude > WaveformConfig.glowThreshold &&
          isActive &&
          edgeFade > 0.3) {
        _glowPaint.color = color.withValues(alpha: 0.25 * edgeFade);
        canvas.drawLine(
          Offset(x, centerY - halfHeight),
          Offset(x, centerY + halfHeight),
          _glowPaint,
        );
      }

      // Main bar (reuse pre-allocated Paint)
      _barPaint.color = color.withValues(alpha: barOpacity);
      canvas.drawLine(
        Offset(x, centerY - halfHeight),
        Offset(x, centerY + halfHeight),
        _barPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    // O(1) comparison using version number
    return version != oldDelegate.version || isActive != oldDelegate.isActive;
  }
}
