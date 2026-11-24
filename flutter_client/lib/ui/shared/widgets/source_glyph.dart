import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:material_ui/material_ui.dart';

/// A transcription source's mark, in one colour like every other icon:
/// your own server, Groq's speed (a bolt), and OpenRouter's logo.
///
/// OpenRouter's mark is its trademark, drawn from the official glyph; the
/// Account panel credits it.
class SourceGlyph extends StatelessWidget {
  const SourceGlyph(
    this.source, {
    super.key,
    this.size = AppSizes.smallIconSize,
    this.color,
  });

  final TranscriptionSource source;
  final double size;

  /// Defaults to the ambient icon colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? IconTheme.of(context).color ?? AppColors.text;

    return switch (source) {
      TranscriptionSource.server => Icon(
        AppIcons.server,
        size: size,
        color: tint,
      ),
      TranscriptionSource.groq => Icon(AppIcons.zap, size: size, color: tint),
      TranscriptionSource.openRouter => CustomPaint(
        size: Size.square(size),
        painter: _OpenRouterMark(tint),
      ),
    };
  }
}

/// OpenRouter's glyph (openrouter.ai/brand), traced from its SVG into a
/// unit square: a ring with the arrow-tailed lozenge around it.
class _OpenRouterMark extends CustomPainter {
  _OpenRouterMark(this.color);

  /// Lucide glyphs leave about a twelfth of their box clear on each side;
  /// the mark keeps the same margin so it sits level with them.
  static const double _inset = 0.08;

  static final Path _unit = Path()
    ..fillType = PathFillType.evenOdd
    ..moveTo(0.75722, 0.177)
    ..cubicTo(0.86384, 0.177, 0.95027, 0.26343, 0.95027, 0.37005)
    ..cubicTo(0.95027, 0.47667, 0.86384, 0.5631, 0.75722, 0.5631)
    ..lineTo(0.9487, 0.75458)
    ..cubicTo(0.97303, 0.77891, 0.9558, 0.8205, 0.92141, 0.8205)
    ..lineTo(0.37112, 0.8205)
    ..cubicTo(0.19343, 0.8205, 0.04938, 0.67644, 0.04938, 0.49875)
    ..cubicTo(0.04938, 0.32105, 0.19343, 0.177, 0.37112, 0.177)
    ..lineTo(0.75722, 0.177)
    ..close()
    ..moveTo(0.37112, 0.3057)
    ..cubicTo(0.26451, 0.3057, 0.17808, 0.39213, 0.17808, 0.49875)
    ..cubicTo(0.17808, 0.60537, 0.26451, 0.6918, 0.37112, 0.6918)
    ..cubicTo(0.47774, 0.6918, 0.56417, 0.60537, 0.56417, 0.49875)
    ..cubicTo(0.56417, 0.39213, 0.47774, 0.3057, 0.37112, 0.3057)
    ..close();

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    final inset = side * _inset;
    canvas
      ..save()
      ..translate(inset, inset)
      ..scale(side * (1 - _inset - _inset))
      ..drawPath(_unit, Paint()..color = color)
      ..restore();
  }

  @override
  bool shouldRepaint(_OpenRouterMark old) => old.color != color;
}
