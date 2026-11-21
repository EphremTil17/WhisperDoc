import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/mappers/home_status_mapper.dart';
import 'package:flutter_client/ui/screens/home/home_navigation.dart';
import 'package:flutter_client/ui/shared/widgets/app_button.dart';
import 'package:flutter_client/ui/shared/widgets/app_dialog.dart';
import 'package:flutter_client/ui/shared/widgets/caption_cue.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';

/// Shown when the server rejects the credentials: what failed and the fix.
class AuthErrorDialog extends StatelessWidget {
  const AuthErrorDialog({super.key, required this.error});

  static const double _maxWidth = 360;

  final String error;

  static void _openSettings(BuildContext context) {
    final navigator = Navigator.of(context)..pop();
    unawaited(HomeNavigation.openSettings(navigator.context));
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Sign-in failed',
      shrinkWrap: true,
      maxWidth: _maxWidth,
      body: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppSpace.md,
          children: [
            const CaptionCue(
              'can’t connect',
              tone: CueTone.alert,
              icon: AppIcons.circleAlert,
            ),
            CrispText(
              '$error. Check your API key or sign-in in Settings.',
              style: AppType.body.copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        spacing: AppSpace.sm,
        children: [
          AppButton(
            label: 'Close',
            tone: AppButtonTone.outline,
            onPressed: () => Navigator.of(context).pop(),
          ),
          AppButton(label: 'Open settings', onPressed: () => _openSettings(context)),
        ],
      ),
    );
  }
}
