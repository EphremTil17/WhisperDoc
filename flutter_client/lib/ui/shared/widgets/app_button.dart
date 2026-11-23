import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:flutter_client/ui/shared/widgets/dashed_outline.dart';

/// The single button component: squared corners, flat fills, 40px tall.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.tone = AppButtonTone.primary,
    this.leading,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonTone tone;

  /// Icon or mark before the label (record dot, stop square, glyph).
  final Widget? leading;

  static const double _padStart = 14;
  static const double _padEnd = 16;
  static const double _pressedAlpha = 0.12;

  @override
  Widget build(BuildContext context) {
    final (Color fill, Color ink) = switch (tone) {
      AppButtonTone.record => (AppColors.record, AppColors.text),
      AppButtonTone.primary => (AppColors.text, AppColors.onLight),
      AppButtonTone.outline => (Colors.transparent, AppColors.text),
    };
    final mark = leading;
    final enabled = onPressed != null;

    final button = TextButton(
      onPressed: onPressed,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(
          Size(0, AppSizes.controlHeight),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsetsDirectional.only(start: _padStart, end: _padEnd),
        ),
        backgroundColor: WidgetStatePropertyAll(
          enabled ? fill : Colors.transparent,
        ),
        foregroundColor: WidgetStatePropertyAll(
          enabled ? ink : AppColors.textMuted,
        ),
        overlayColor: WidgetStatePropertyAll(
          ink.withValues(alpha: _pressedAlpha),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: AppRadius.controlAll,
            side: tone == AppButtonTone.outline && enabled
                ? const BorderSide(color: AppColors.outline)
                : BorderSide.none,
          ),
        ),
        splashFactory: NoSplash.splashFactory,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: AppSpace.sm,
        children: [
          ?mark,
          CrispText(
            label,
            style: AppType.body.copyWith(
              fontWeight: FontWeight.w500,
              color: enabled ? ink : AppColors.textMuted,
            ),
          ),
        ],
      ),
    );

    // Unavailable controls get a dashed outline instead of a solid one.
    return enabled ? button : DashedOutline(child: button);
  }
}

/// The three button roles the design uses.
enum AppButtonTone {
  /// Crimson fill: start or stop recording only.
  record,

  /// Light fill: the one fix for a blocked state.
  primary,

  /// Outline: secondary actions next to a primary one.
  outline,
}
