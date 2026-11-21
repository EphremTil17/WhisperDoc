import 'dart:async';

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/ui/screens/home/dialogs/profile_hub_dialog_content.dart';
import 'package:flutter_client/ui/screens/home/home_navigation.dart';

/// Mode-aware Profile Hub Dialog.
///
/// In backend mode: shows OIDC identity, update status, sign in/out.
/// In Groq mode: shows Groq Cloud status and a path to switch to WhisperDoc.
class ProfileHubDialog extends StatelessWidget {
  const ProfileHubDialog({super.key});

  static const double _dialogWidth = 320;
  static const double _dialogPadding = 24;

  /// Closes this dialog, then opens the log viewer from the home screen.
  static void _openLogs(BuildContext context) {
    final navigator = Navigator.of(context)..pop();
    unawaited(HomeNavigation.openLogs(navigator.context));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: AppRadius.controlAll,
        side: BorderSide(color: AppColors.rule),
      ),
      child: SizedBox(
        width: _dialogWidth,
        child: Padding(
          padding: const EdgeInsets.all(_dialogPadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ProfileHubDialogContent(),
              // Diagnostics live with the account: they answer "is it
              // working?", not "how should it behave?".
              TextButton.icon(
                onPressed: () => _openLogs(context),
                icon: const Icon(
                  LucideIcons.fileText,
                  size: AppSizes.smallIconSize,
                ),
                label: const Text('Logs', style: AppType.caption),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
