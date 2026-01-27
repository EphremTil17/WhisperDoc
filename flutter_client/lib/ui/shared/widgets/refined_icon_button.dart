import 'package:flutter/material.dart';

class RefinedIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? iconColor;
  final double iconSize;
  final bool isPulsing;
  final Color? pulseColor;

  const RefinedIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.iconColor,
    this.iconSize = 24,
    this.isPulsing = false,
    this.pulseColor,
  });

  @override
  State<RefinedIconButton> createState() => _RefinedIconButtonState();
}

class _RefinedIconButtonState extends State<RefinedIconButton> with SingleTickerProviderStateMixin {
  bool _isHovering = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    if (widget.isPulsing) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(RefinedIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPulsing != oldWidget.isPulsing) {
      if (widget.isPulsing) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            final pulseVal = widget.isPulsing ? _pulseAnimation.value : 0.0;
            final glowColor = widget.pulseColor ?? Colors.white;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _isHovering
                    ? Colors.white.withValues(alpha: 0.2)
                    : glowColor.withValues(alpha: 0.08 + (pulseVal * 0.05)),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _isHovering
                      ? Colors.white.withValues(alpha: 0.5)
                      : widget.isPulsing
                          ? glowColor.withValues(alpha: 0.15 + (pulseVal * 0.35))
                          : Colors.white.withValues(alpha: 0.15),
                  width: widget.isPulsing ? 1.0 + (pulseVal * 0.5) : 1.0,
                ),
                boxShadow: widget.isPulsing
                    ? [
                        BoxShadow(
                          color: glowColor.withValues(alpha: 0.1 * pulseVal),
                          blurRadius: 8.0 * pulseVal,
                          spreadRadius: 1.0 * pulseVal,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                widget.icon,
                color: _isHovering
                    ? Colors.white
                    : (widget.iconColor ?? Colors.white70),
                size: widget.iconSize,
              ),
            );
          },
        ),
      ),
    );
  }
}
