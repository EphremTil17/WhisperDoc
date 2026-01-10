import 'package:flutter/material.dart';

class RefinedIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? iconColor;
  final double iconSize;

  const RefinedIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.iconColor,
    this.iconSize = 24,
  });

  @override
  State<RefinedIconButton> createState() => _RefinedIconButtonState();
}

class _RefinedIconButtonState extends State<RefinedIconButton> {
  bool _isHovering = false;

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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _isHovering
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _isHovering
                  ? Colors.white.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.15),
            ),
          ),
          child: Icon(
            widget.icon,
            color: _isHovering
                ? Colors.white
                : (widget.iconColor ?? Colors.white70),
            size: widget.iconSize,
          ),
        ),
      ),
    );
  }
}
