import 'package:flutter/material.dart';

class FloatingCapsule extends StatefulWidget {
  final bool isRecording;
  final bool enabled;
  final VoidCallback onTap;

  const FloatingCapsule({
    super.key,
    required this.isRecording,
    required this.onTap,
    this.enabled = true,
  });

  @override
  State<FloatingCapsule> createState() => _FloatingCapsuleState();
}

class _FloatingCapsuleState extends State<FloatingCapsule> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    // Determine status color/text based on state
    final color = widget.isRecording
        ? const Color(0xFFDC143C)
        : (widget.enabled ? Colors.white24 : Colors.white10);
    final text = widget.isRecording
        ? "Stop Recording"
        : (widget.enabled ? "Ready" : "Offline");

    final opacity = widget.enabled ? 1.0 : 0.4;

    return MouseRegion(
      onEnter: widget.enabled
          ? (_) => setState(() => _isHovering = true)
          : null,
      onExit: widget.enabled
          ? (_) => setState(() => _isHovering = false)
          : null,
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: widget.isRecording
                ? color.withValues(alpha: _isHovering ? 0.9 : 1.0)
                : color.withValues(alpha: _isHovering ? 0.2 : 0.1),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: widget.isRecording
                  ? Colors.redAccent
                  : (widget.enabled
                        ? (_isHovering ? Colors.white54 : Colors.white24)
                        : Colors.white10),
              width: 1,
            ),
            boxShadow: [
              if (widget.enabled)
                BoxShadow(
                  color:
                      (widget.isRecording
                              ? const Color(0xFFDC143C)
                              : Colors.black)
                          .withValues(alpha: _isHovering ? 0.4 : 0.3),
                  blurRadius: _isHovering ? 25 : 20,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Opacity(
            opacity: opacity,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.isRecording ? Icons.stop : Icons.mic,
                  color: widget.enabled ? Colors.white : Colors.white38,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  text,
                  style: TextStyle(
                    color: widget.enabled ? Colors.white : Colors.white38,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
