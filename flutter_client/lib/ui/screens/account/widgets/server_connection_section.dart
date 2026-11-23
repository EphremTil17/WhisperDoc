import 'dart:async';

import 'package:flutter_client/controllers/profile_controller.dart';
import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/account/account_fields.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:flutter_client/ui/shared/widgets/panel/panel_row.dart';
import 'package:flutter_client/ui/shared/widgets/panel/panel_section.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Self-hosted connection: the server address, sign-in, and the developer
/// key for servers without sign-in.
class ServerConnectionSection extends StatelessWidget {
  const ServerConnectionSection({super.key});

  /// The cause is in the log; the user only needs to know it did not work.
  static Future<void> _signIn(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<ProfileController>().signIn();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: CrispText(
            "Couldn't sign in. Details are in Logs.",
            style: AppType.caption,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final profile = context.watch<ProfileController>();
    // Each of these reconnects, which would cut off a dictation under way.
    final locked = context.select((RecordingController c) => c.isSessionActive);
    final lockNote = locked ? PanelRow.lockedWhileRecording : null;
    final address = Uri.tryParse(settings.serverUri);
    final hasDeveloperKey = settings.cachedApiKey?.isNotEmpty ?? false;
    // Signing in is the fix when nothing else lets the app connect.
    final needsSignIn = !profile.isAuthenticated && !hasDeveloperKey;

    return PanelSection(
      label: 'Connection',
      children: [
        PanelRow(
          icon: AppIcons.server,
          label: 'Server',
          subtitle: lockNote,
          value: address == null || address.host.isEmpty
              ? settings.serverUri
              : address.authority,
          enabled: !locked,
          onTap: () => unawaited(AccountFields.server(context)),
        ),
        if (!profile.isAuthenticated)
          PanelRow(
            icon: AppIcons.logIn,
            iconColor: needsSignIn ? AppColors.alert : null,
            label: 'Sign in',
            subtitle: lockNote,
            value: 'Passkey or Google',
            valueColor: needsSignIn ? AppColors.alert : null,
            enabled: !locked,
            onTap: () => unawaited(_signIn(context)),
          ),
        PanelRow(
          icon: AppIcons.keyRound,
          label: 'Developer key',
          subtitle: lockNote,
          value: hasDeveloperKey ? 'Set' : 'Not set',
          enabled: !locked,
          onTap: () => unawaited(AccountFields.developerKey(context)),
        ),
      ],
    );
  }
}
