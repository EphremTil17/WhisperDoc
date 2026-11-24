import 'dart:async';

import 'package:flutter_client/controllers/profile_controller.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/shared/widgets/app_link.dart';
import 'package:flutter_client/ui/shared/widgets/confirm_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// The way out of the current source: remove its API key, or sign out of
/// the server. The Account panel shows it only when there is something to
/// leave.
class AccountExitLink extends StatelessWidget {
  const AccountExitLink({super.key});

  static Future<void> _removeKey(
    BuildContext context,
    TranscriptionSource source,
  ) async {
    final settings = context.read<SettingsService>();
    final confirmed = await ConfirmDialog.ask(
      context,
      title: 'Remove API key?',
      message:
          'WhisperDoc stops transcribing with ${source.label} until you add '
          'a key again.',
      confirmLabel: 'Remove',
    );
    if (!confirmed) return;
    await switch (source) {
      TranscriptionSource.groq => settings.setGroqApiKey(''),
      TranscriptionSource.openRouter => settings.setOpenRouterApiKey(''),
      TranscriptionSource.server => Future.value(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final source = context.select((SettingsService s) => s.transcriptionSource);
    // Leaving would cut off the dictation under way.
    final locked = context.select((RecordingController c) => c.isSessionActive);
    final VoidCallback leave = source.isCloud
        ? () => unawaited(_removeKey(context, source))
        : () => unawaited(context.read<ProfileController>().signOut());

    return Align(
      alignment: AlignmentDirectional.centerStart,
      // The link's own 8px padding hangs into the footer inset, so its text
      // lines up with the row icons above.
      child: Transform.translate(
        offset: const Offset(-AppSpace.sm, 0),
        child: AppLink(
          label: source.isCloud ? 'Remove API key' : 'Sign out',
          color: AppColors.alert,
          onPressed: locked ? null : leave,
        ),
      ),
    );
  }
}
