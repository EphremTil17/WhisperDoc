import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';

/// Paints a 1px dashed rectangle over its child: the "unavailable" outline
/// for a control that cannot be used right now. Dashes land on whole pixels.
class DashedOutline extends StatelessWidget {
  const DashedOutline({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(foregroundPainter: const _DashedRectPainter(), child: child);
  }
}

class _DashedRectPainter extends CustomPainter {
  const _DashedRectPainter();

  static const double _dash = 3;
  static const double _gap = 3;

  /// Centres a 1px stroke on the pixel grid.
  static const double _inset = 0.5;

  static final Paint _paint = Paint()
    ..color = AppColors.outline
    ..strokeWidth = 1;

  @override
  void paint(Canvas canvas, Size size) {
    final left = _inset;
    final top = _inset;
    final right = size.width.floorToDouble() - _inset;
    final bottom = size.height.floorToDouble() - _inset;
    _line(canvas, Offset(left, top), Offset(right, top));
    _line(canvas, Offset(right, top), Offset(right, bottom));
    _line(canvas, Offset(right, bottom), Offset(left, bottom));
    _line(canvas, Offset(left, bottom), Offset(left, top));
  }

  void _line(Canvas canvas, Offset from, Offset to) {
    final length = (to - from).distance;
    final direction = (to - from) / length;
    for (var d = 0.0; d < length; d += _dash + _gap) {
      final end = d + _dash < length ? d + _dash : length;
      canvas.drawLine(from + direction * d, from + direction * end, _paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRectPainter oldDelegate) => false;
}
