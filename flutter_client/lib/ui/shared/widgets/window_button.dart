import 'package:flutter/material.dart';

class WindowButton extends StatefulWidget {
  const WindowButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;

  @override
  State<WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<WindowButton> {
  static const _animationDuration = Duration(milliseconds: 200);
  static const _buttonWidth = 32.0;
  static const _buttonHeight = 24.0;
  static const _cornerRadius = 4.0;
  static const _iconSize = 14.0;
  static const _hoverAlpha = 0.1;

  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final hoverColor = widget.isClose
        ? Colors.red
        : Colors.white.withValues(alpha: _hoverAlpha);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: _animationDuration,
          width: _buttonWidth,
          height: _buttonHeight,
          decoration: BoxDecoration(
            color: _isHovered ? hoverColor : Colors.transparent,
            borderRadius: const BorderRadius.all(
              Radius.circular(_cornerRadius),
            ),
          ),
          child: Icon(widget.icon, size: _iconSize, color: Colors.white),
        ),
      ),
    );
  }
}
