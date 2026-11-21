import 'dart:async';

import 'package:flutter_client/controllers/profile_controller.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/shared/widgets/app_link.dart';
import 'package:flutter_client/ui/shared/widgets/confirm_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// The way out of the current service: remove the Groq key, or sign out.
/// The Account panel shows it only when there is something to leave.
class AccountExitLink extends StatelessWidget {
  const AccountExitLink({super.key});

  static Future<void> _removeGroqKey(BuildContext context) async {
    final settings = context.read<SettingsService>();
    final confirmed = await ConfirmDialog.ask(
      context,
      title: 'Remove API key?',
      message: 'WhisperDoc stops transcribing until you add a key again.',
      confirmLabel: 'Remove',
    );
    if (confirmed) await settings.setGroqApiKey('');
  }

  @override
  Widget build(BuildContext context) {
    final isGroqMode = context.select((SettingsService s) => s.isGroqMode);

    return Align(
      alignment: AlignmentDirectional.centerStart,
      // The link's own 8px padding hangs into the footer inset, so its text
      // lines up with the row icons above.
      child: Transform.translate(
        offset: const Offset(-AppSpace.sm, 0),
        child: AppLink(
          label: isGroqMode ? 'Remove API key' : 'Sign out',
          color: AppColors.alert,
          onPressed: isGroqMode
              ? () => unawaited(_removeGroqKey(context))
              : () => unawaited(context.read<ProfileController>().signOut()),
        ),
      ),
    );
  }
}
