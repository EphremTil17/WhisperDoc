import 'package:flutter/material.dart';

/// Wraps an action control with an animated opacity lock and disabled tooltip
/// during active recording sessions.
class LockableControl extends StatelessWidget {
  const LockableControl({
    super.key,
    required this.locked,
    required this.child,
    this.tooltipMessage = 'Unavailable while recording',
  });

  static const double _defaultTooltipVerticalOffset = 20;
  static const double _lockedOpacity = 0.35;

  final bool locked;
  final Widget child;
  final String tooltipMessage;

  @override
  Widget build(BuildContext context) {
    final content = IgnorePointer(
      ignoring: locked,
      child: AnimatedOpacity(
        opacity: locked ? _lockedOpacity : 1.0,
        duration: const Duration(milliseconds: 150),
        child: child,
      ),
    );

    if (locked) {
      return Tooltip(
        message: tooltipMessage,
        preferBelow: false,
        verticalOffset: _defaultTooltipVerticalOffset,
        child: content,
      );
    }

    return content;
  }
}
