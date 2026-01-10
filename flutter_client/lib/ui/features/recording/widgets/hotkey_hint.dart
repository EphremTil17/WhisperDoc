import 'package:flutter/material.dart';
import 'package:flutter_client/core/services/settings_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class HotkeyHint extends StatelessWidget {
  const HotkeyHint({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontFamily: GoogleFonts.lexend().fontFamily,
          ),
          children: [
            const TextSpan(text: 'Press '),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  settings.globalHotkey,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontFamily: GoogleFonts.lexend().fontFamily,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const TextSpan(text: ' to start recording'),
          ],
        ),
      ),
    );
  }
}
