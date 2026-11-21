import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';

/// The app's single theme, built from the tokens in app_tokens.dart. Material
/// components that are not hand-built (inputs, switches, icon
/// buttons, tooltips, snackbars) take the Captions look from here.
class AppTheme {
  static const double _selectionAlpha = 0.45;

  static ThemeData get darkTheme {
    final base = ThemeData.dark().textTheme;

    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.ground,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.record,
        secondary: AppColors.alert,
        surface: AppColors.surface,
        onSurface: AppColors.text,
        outline: AppColors.outline,
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
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface,
        contentTextStyle: AppType.caption,
        insetPadding: EdgeInsets.all(AppSpace.lg),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.controlAll,
          side: BorderSide(color: AppColors.rule),
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
      // Shared look for panel and dialog inputs; fields override only
      // what differs (padding, hints, error borders).
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.ground,
        isDense: true,
        // 24px line + 8px above and below: a 40px control.
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.sm,
        ),
        // Placeholders must not read as values.
        hintStyle: AppType.body.copyWith(color: AppColors.textMuted),
        errorStyle: AppType.caption.copyWith(color: AppColors.alert),
        errorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.controlAll,
          borderSide: BorderSide(color: AppColors.alert),
        ),
        focusedErrorBorder: const OutlineInputBorder(
          borderRadius: AppRadius.controlAll,
          borderSide: BorderSide(color: AppColors.alert),
        ),
        border: const OutlineInputBorder(
          borderRadius: AppRadius.controlAll,
          borderSide: BorderSide(color: AppColors.rule),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadius.controlAll,
          borderSide: BorderSide(color: AppColors.rule),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadius.controlAll,
          borderSide: BorderSide(color: AppColors.textMuted),
        ),
      ),
      switchTheme: SwitchThemeData(
        // "On" is white, not crimson: crimson means recording or "needs you".
        // Disabled reads as off whatever the value, so it never shows white.
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) &&
                  !s.contains(WidgetState.disabled)
              ? AppColors.ground
              : AppColors.iconFaint,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) &&
                  !s.contains(WidgetState.disabled)
              ? AppColors.text
              : Colors.transparent,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => switch (s) {
            _ when s.contains(WidgetState.disabled) => AppColors.rule,
            _ when s.contains(WidgetState.selected) => AppColors.text,
            _ => AppColors.outline,
          },
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.rule, space: 1),
      textTheme: base.apply(
        fontFamily: AppType.family,
        bodyColor: AppColors.text,
        displayColor: AppColors.text,
      ),
      iconTheme: const IconThemeData(color: AppColors.textMuted),
    );
  }
}
