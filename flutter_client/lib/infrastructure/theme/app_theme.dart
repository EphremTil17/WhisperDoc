import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';

class AppTheme {
  static const Color crimsonPrimary = Color(0xFFDC143C); // Crimson
  static const Color crimsonDark = Color(0xFF990000); // Darker Crimson
  static const Color backgroundStart = Color(0xFF1a0a0f); // Dark gradient start
  static const Color backgroundEnd = Color(0xFF2d0a1a); // Dark gradient end
  static const Color surface = Color(0xCC1E1E23); // Semi-transparent surface
  static const Color glassBorder = Color(0x1AFFFFFF); // White with low opacity
  static const Color cardBackground = Color(0x0DFFFFFF); // Very subtle white

  static const double _selectionAlpha = 0.45;
  static const double _shadowAlpha = 0.2;
  static const double _shadowBlur = 16;

  static ThemeData get darkTheme {
    final base = ThemeData.dark().textTheme;

    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.ground,
      colorScheme: const ColorScheme.dark(
        primary: crimsonPrimary,
        secondary: crimsonDark,
        surface: surface,
        onSurface: Colors.white,
      ),
      fontFamily: AppType.family,
      // Theme the parts we did not draw: selection and the caret.
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.text,
        selectionColor: AppColors.record.withValues(alpha: _selectionAlpha),
        selectionHandleColor: AppColors.record,
      ),
      // Every IconButton: 40px square target, flat hover, no ink splash.
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          fixedSize: const Size.square(AppSizes.iconButton),
          iconSize: AppSizes.iconSize,
          padding: EdgeInsets.zero,
          foregroundColor: AppColors.textMuted,
          disabledForegroundColor: AppColors.iconFaint,
          hoverColor: AppColors.band,
          highlightColor: AppColors.band,
          shape: const RoundedRectangleBorder(
            borderRadius: AppRadius.controlAll,
          ),
          splashFactory: NoSplash.splashFactory,
        ),
      ),
      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.band,
          borderRadius: AppRadius.controlAll,
        ),
        textStyle: AppType.caption,
        padding: EdgeInsets.symmetric(
          horizontal: AppSpace.sm,
          vertical: AppSpace.xs,
        ),
        waitDuration: Duration(milliseconds: 400),
      ),
      // Shared look for settings inputs and dropdowns; fields override only
      // what differs (padding, hints, error borders).
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide.none,
        ),
      ),
      textTheme: base.apply(
        fontFamily: AppType.family,
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
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
    border: const Border.fromBorderSide(BorderSide(color: glassBorder)),
    borderRadius: const BorderRadius.all(Radius.circular(16)),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: _shadowAlpha),
        blurRadius: _shadowBlur,
        offset: const Offset(0, 4),
      ),
    ],
  );

  static const TextStyle sectionTitleStyle = TextStyle(
    color: Colors.white54,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.0,
  );
}
