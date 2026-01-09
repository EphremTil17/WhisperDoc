import 'package:flutter/material.dart';

class FloatingCapsule extends StatefulWidget {
  final bool isRecording;
  final VoidCallback onTap;

  const FloatingCapsule({
    super.key,
    required this.isRecording,
    required this.onTap,
  });

  @override
  State<FloatingCapsule> createState() => _FloatingCapsuleState();
}

class _FloatingCapsuleState extends State<FloatingCapsule> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    // Determine status color/text based on state
    final color = widget.isRecording ? const Color(0xFFDC143C) : Colors.white24;
    final text = widget.isRecording ? "Stop Recording" : "Ready";

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
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
                  : (_isHovering ? Colors.white54 : Colors.white24),
              width: 1,
            ),
            boxShadow: [
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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.isRecording ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
