import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class CustomTitleBar extends StatelessWidget {
  const CustomTitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32, // Standard title bar height
      child: Row(
        children: [
          // Drag Region (Takes up most space)
          Expanded(
            child: GestureDetector(
              onTap: () {}, // Capture taps to prevent passing through
              child: DragToMoveArea(
                child: Container(
                  color: Colors.transparent,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 16),
                ),
              ),
            ),
          ),

          // Window Controls
          _WindowButton(
            icon: Icons.minimize,
            onPressed: () => windowManager.minimize(),
          ),
          _WindowButton(
            icon: Icons.close,
            isClose: true,
            onPressed: () => windowManager.close(),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 32,
          height: 24, // Smaller height for sleek look
          decoration: BoxDecoration(
            color: _isHovered
                ? (widget.isClose
                      ? Colors.red
                      : Colors.white.withValues(alpha: 0.1))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(widget.icon, size: 14, color: Colors.white),
        ),
      ),
    );
  }
}
