import 'package:flutter/material.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class HotkeyHint extends StatelessWidget {
  const HotkeyHint({super.key});

  static const _outerAlpha = 0.05;
  static const _outerRadius = 8.0;
  static const _borderAlpha = 0.1;
  static const _hintFontSize = 12.0;
  static const _keyFontSize = 11.0;
  static const _keyAlpha = 0.1;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final fontFamily = GoogleFonts.lexend().fontFamily;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: _outerAlpha),
        borderRadius: const BorderRadius.all(Radius.circular(_outerRadius)),
        border: Border.all(color: Colors.white.withValues(alpha: _borderAlpha)),
      ),
      child: Text.rich(
        TextSpan(
          style: TextStyle(
            color: Colors.white54,
            fontSize: _hintFontSize,
            fontFamily: fontFamily,
          ),
          children: [
            const TextSpan(text: 'Press '),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: _keyAlpha),
                  borderRadius: const BorderRadius.all(Radius.circular(4)),
                ),
                child: Text(
                  settings.globalHotkey,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: _keyFontSize,
                    fontFamily: fontFamily,
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
