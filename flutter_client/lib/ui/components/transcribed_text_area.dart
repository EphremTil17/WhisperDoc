import 'package:flutter/material.dart';
import 'package:flutter_client/ui/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

class TranscribedTextArea extends StatelessWidget {
  final String text;

  const TranscribedTextArea({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 200, // Fixed height to fit the area highlighted in yellow
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.glassDecoration.copyWith(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Stack(
        children: [
          SingleChildScrollView(
            reverse: true, // Always show the latest transcription
            child: Text(
              text.isEmpty ? 'Transcription will appear here...' : text,
              style: TextStyle(
                fontSize: 16,
                height: 1.5,
                color: text.isEmpty ? Colors.white38 : Colors.white,
                fontFamily: GoogleFonts.lexend().fontFamily,
              ),
              overflow: TextOverflow.visible,
            ),
          ),
        ],
      ),
    );
  }
}
