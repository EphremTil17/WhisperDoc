import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/shared/widgets/app_button.dart';
import 'package:flutter_client/ui/shared/widgets/app_dialog.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';

/// Confirms turning incognito on, because it deletes local history.
/// Pops `true` to turn it on, `false` to cancel.
class IncognitoToggleDialog extends StatelessWidget {
  const IncognitoToggleDialog({super.key});

  static const double _maxWidth = 360;

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Turn on incognito?',
      shrinkWrap: true,
      maxWidth: _maxWidth,
      body: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: CrispText(
          'This permanently deletes your local transcription history. '
          'Nothing new is saved while incognito is on.',
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
            label: 'Turn on',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
  }
}
