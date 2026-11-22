import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';

/// Text set like broadcast captions: centred lines, each on its own solid
/// band. A render object rather than a CustomPaint so the text is laid out
/// once per change, the painter is disposed, and screen readers get the text.
class CaptionBand extends LeafRenderObjectWidget {
  const CaptionBand(
    this.text, {
    super.key,
    this.style = AppType.captionBand,
    this.maxLines = _defaultMaxLines,
  });

  static const int _defaultMaxLines = 3;

  final String text;
  final TextStyle style;
  final int maxLines;

  @override
  RenderCaptionBand createRenderObject(BuildContext context) =>
      RenderCaptionBand(
        text: text,
        style: style,
        maxLines: maxLines,
        textDirection: Directionality.of(context),
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      );

  @override
  void updateRenderObject(BuildContext context, RenderCaptionBand renderObject) {
    renderObject
      ..text = text
      ..style = style
      ..maxLines = maxLines
      ..textDirection = Directionality.of(context)
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

class RenderCaptionBand extends RenderBox {
  RenderCaptionBand({
    required String text,
    required TextStyle style,
    required int maxLines,
    required TextDirection textDirection,
    required this._devicePixelRatio,
  }) : _text = text,
       _style = style,
       _painter = TextPainter(
         text: TextSpan(text: text, style: style),
         textAlign: TextAlign.center,
         textDirection: textDirection,
         maxLines: maxLines,
         ellipsis: '…',
       );

  /// Band padding around each line's glyphs.
  static const double _padX = 10;
  static const double _padY = 3;
  static const double _half = 2;
  static final Paint _bandPaint = Paint()..color = AppColors.band;

  final TextPainter _painter;
  String _text;
  TextStyle _style;
  double _devicePixelRatio;

  set text(String value) {
    if (value == _text) return;
    _text = value;
    _relayoutText();
    markNeedsSemanticsUpdate();
  }

  set style(TextStyle value) {
    if (value == _style) return;
    _style = value;
    _relayoutText();
  }

  set maxLines(int value) {
    if (value == _painter.maxLines) return;
    _painter.maxLines = value;
    markNeedsLayout();
  }

  void _relayoutText() {
    _painter.text = TextSpan(text: _text, style: _style);
    markNeedsLayout();
  }

  set textDirection(TextDirection value) {
    if (value == _painter.textDirection) return;
    _painter.textDirection = value;
    markNeedsLayout();
  }

  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  double _snap(double v) =>
      (v * _devicePixelRatio).roundToDouble() / _devicePixelRatio;

  @override
  void performLayout() {
    _painter.layout(maxWidth: constraints.maxWidth - _padX * _half);
    size = constraints.constrain(
      Size(constraints.maxWidth, _painter.height),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final origin = Offset(
      _snap(offset.dx + (size.width - _painter.width) / _half),
      _snap(offset.dy),
    );
    final boxes = _painter.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: _text.length),
    );
    final canvas = context.canvas;
    for (final box in boxes) {
      final rect = box.toRect().shift(origin);
      canvas.drawRect(
        Rect.fromLTRB(
          _snap(rect.left - _padX),
          _snap(rect.top - _padY),
          _snap(rect.right + _padX),
          _snap(rect.bottom + _padY),
        ),
        _bandPaint,
      );
    }
    _painter.paint(canvas, origin);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _text
      ..textDirection = _painter.textDirection;
  }

  @override
  void dispose() {
    _painter.dispose();
    super.dispose();
  }
}
