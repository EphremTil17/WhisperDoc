import 'package:flutter/material.dart';

class FloatingCapsule extends StatelessWidget {
  final bool isRecording;
  final VoidCallback onTap;

  const FloatingCapsule({
    super.key,
    required this.isRecording,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Determine status color/text based on state
    final color = isRecording ? const Color(0xFFDC143C) : Colors.white24;
    final text = isRecording ? "Stop Recording" : "Ready";

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isRecording ? 1.0 : 0.1),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isRecording ? Colors.redAccent : Colors.white24,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: (isRecording ? const Color(0xFFDC143C) : Colors.black)
                  .withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isRecording ? Icons.stop : Icons.mic,
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
    );
  }
}
