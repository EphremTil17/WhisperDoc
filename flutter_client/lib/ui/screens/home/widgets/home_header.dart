import 'package:flutter/material.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        SizedBox(height: 16),
        Text(
          'WhisperDoc',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: -1.0,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'AI-Powered Speech-to-Text Dictation',
          style: TextStyle(fontSize: 12, color: Colors.white54),
        ),
      ],
    );
  }
}
