import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';

/// The one press response: the content drops [AppSizes.pressDepth] pixels
/// the instant the pointer goes down, and climbs back a pixel per
/// [AppMotion.pressStep] when it lifts, like a key. Whole pixels keep
/// CrispText sharp, and the steps (not an eased slide) match the pixel meter.
/// No ticker: two timer steps per press.
///
/// Listens to raw pointer events, not the tap gesture: inside a scrolling
/// list a tap is only recognised after a delay, so a quick click would
/// otherwise never show. Buttons get it from the theme (`backgroundBuilder`);
/// other tap targets wrap their content in it.
class PressNudge extends StatefulWidget {
  const PressNudge({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<PressNudge> createState() => _PressNudgeState();
}

class _PressNudgeState extends State<PressNudge> {
  int _depth = 0;
  Timer? _step;

  void _down(PointerDownEvent _) {
    if (!widget.enabled) return;
    _step?.cancel();
    setState(() => _depth = AppSizes.pressDepth);
  }

  void _up(PointerEvent _) {
    if (_depth > 0) _climb();
  }

  void _climb() {
    _step?.cancel();
    _step = Timer(AppMotion.pressStep, _rise);
  }

  void _rise() {
    if (!mounted || _depth <= 0) return;
    setState(() => _depth--);
    if (_depth > 0) _climb();
  }

  @override
  void dispose() {
    _step?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      // The whole area, padding included, not just the label's glyphs.
      behavior: HitTestBehavior.opaque,
      onPointerDown: _down,
      onPointerUp: _up,
      onPointerCancel: _up,
      child: Transform.translate(
        offset: Offset(0, _depth.toDouble()),
        child: widget.child,
      ),
    );
  }
}
