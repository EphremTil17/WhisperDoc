import 'package:flutter/material.dart';

class IncognitoToggleDialog extends StatelessWidget {
  const IncognitoToggleDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1a1a2e),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      title: const Row(
        children: [
          Icon(Icons.visibility_off, color: Colors.orangeAccent, size: 24),
          SizedBox(width: 12),
          Text(
            'Enable Incognito Mode?',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
      content: const Text(
        'This will permanently delete your local transcription history. '
        'New transcriptions will not be saved while incognito mode is active.',
        style: TextStyle(color: Colors.white70, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(
            backgroundColor: Colors.orangeAccent.withValues(alpha: 0.2),
          ),
          child: const Text(
            'Enable',
            style: TextStyle(color: Colors.orangeAccent),
          ),
        ),
      ],
    );
  }
}
