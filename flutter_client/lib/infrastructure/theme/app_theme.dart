import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color crimsonPrimary = Color(0xFFDC143C); // Crimson
  static const Color crimsonDark = Color(0xFF990000); // Darker Crimson
  static const Color backgroundStart = Color(0xFF1a0a0f); // Dark gradient start
  static const Color backgroundEnd = Color(0xFF2d0a1a); // Dark gradient end
  static const Color surface = Color(0xCC1E1E23); // Semi-transparent surface
  static const Color glassBorder = Color(0x1AFFFFFF); // White with low opacity
  static const Color cardBackground = Color(0x0DFFFFFF); // Very subtle white

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.transparent, // For custom gradients
      colorScheme: const ColorScheme.dark(
        primary: crimsonPrimary,
        secondary: crimsonDark,
        surface: surface,
        onSurface: Colors.white,
      ),
      fontFamily: GoogleFonts.lexend().fontFamily,
      textTheme: GoogleFonts.lexendTextTheme(
        ThemeData.dark().textTheme,
      ).apply(bodyColor: Colors.white, displayColor: Colors.white),
      iconTheme: const IconThemeData(color: Colors.white70),
    );
  }

  static BoxDecoration get mainGradient => const BoxDecoration(
    gradient: LinearGradient(
      colors: [backgroundStart, backgroundEnd],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );

  static BoxDecoration get glassDecoration => BoxDecoration(
    color: surface,
    border: Border.all(color: glassBorder),
    borderRadius: BorderRadius.circular(16),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.2),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ],
  );

  static TextStyle get sectionTitleStyle => const TextStyle(
    color: Colors.white54,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.0,
  );

  static TextStyle get subtitleStyle =>
      const TextStyle(fontSize: 11, color: Colors.white38);
}
