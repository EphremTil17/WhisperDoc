import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:material_ui/material_ui.dart';

/// A quiet text action, underlined: `Switch service`, `Remove API key`.
/// For actions that sit beside content rather than ending a flow.
class AppLink extends StatelessWidget {
  const AppLink({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColors.text,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Ink colour; alert for destructive links.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ink = onPressed == null ? AppColors.textMuted : color;

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, AppSizes.controlHeight),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
        overlayColor: AppColors.band,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.controlAll),
        splashFactory: NoSplash.splashFactory,
      ),
      child: CrispText(
        label,
        style: AppType.caption.copyWith(
          color: ink,
          fontWeight: FontWeight.w500,
          decoration: TextDecoration.underline,
          decorationColor: ink,
        ),
      ),
    );
  }
}
