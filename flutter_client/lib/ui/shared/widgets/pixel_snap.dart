import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

/// Paints its child at the nearest whole device pixel.
///
/// Flutter on Windows draws text with greyscale antialiasing and no hinting,
/// so a line laid out at a fractional y (centred content, odd sizes) smears
/// its horizontal strokes across two pixel rows. Snapping the paint origin
/// keeps baselines on the pixel grid; combined with the integer-baseline type
/// scale in AppType this is what makes text read sharp. Layout and hit
/// testing are unchanged (the shift is under half a pixel).
class PixelSnap extends SingleChildRenderObjectWidget {
  const PixelSnap({super.key, super.child});

  @override
  RenderPixelSnap createRenderObject(BuildContext context) =>
      RenderPixelSnap(MediaQuery.devicePixelRatioOf(context));

  @override
  void updateRenderObject(BuildContext context, RenderPixelSnap renderObject) {
    renderObject.devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

class RenderPixelSnap extends RenderProxyBox {
  RenderPixelSnap(this._devicePixelRatio);

  double _devicePixelRatio;

  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  double _snap(double logical) =>
      (logical * _devicePixelRatio).roundToDouble() / _devicePixelRatio;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    context.paintChild(child, Offset(_snap(offset.dx), _snap(offset.dy)));
  }
}
