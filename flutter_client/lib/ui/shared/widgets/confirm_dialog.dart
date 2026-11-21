import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/shared/widgets/app_button.dart';
import 'package:flutter_client/ui/shared/widgets/app_dialog.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:material_ui/material_ui.dart';

/// Asks before something that cannot be undone. Pops `true` to go ahead.
///
/// ```dart
/// final ok = await ConfirmDialog.ask(context, title: 'Remove key?', ...);
/// ```
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

  static const double _maxWidth = 360;

  final String title;
  final String message;
  final String confirmLabel;

  /// Shows the dialog; true only when the user confirmed.
  static Future<bool> ask(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => ConfirmDialog(
          title: title,
          message: message,
          confirmLabel: confirmLabel,
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: title,
      shrinkWrap: true,
      maxWidth: _maxWidth,
      body: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: CrispText(
          message,
          style: AppType.body.copyWith(color: AppColors.textMuted),
        ),
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        spacing: AppSpace.sm,
        children: [
          AppButton(
            label: 'Cancel',
            tone: AppButtonTone.outline,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          AppButton(
            label: confirmLabel,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }
}
