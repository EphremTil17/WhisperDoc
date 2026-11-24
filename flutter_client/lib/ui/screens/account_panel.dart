import 'package:flutter_client/controllers/profile_controller.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/account/widgets/account_exit_link.dart';
import 'package:flutter_client/ui/screens/account/widgets/account_identity.dart';
import 'package:flutter_client/ui/screens/account/widgets/app_info_section.dart';
import 'package:flutter_client/ui/screens/account/widgets/groq_connection_section.dart';
import 'package:flutter_client/ui/screens/account/widgets/open_router_connection_section.dart';
import 'package:flutter_client/ui/screens/account/widgets/server_connection_section.dart';
import 'package:flutter_client/ui/shared/widgets/panel/app_panel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Is it working? Where dictation goes and who is signed in, that source's
/// connection values, then the app's version and logs for when it is not.
class AccountPanel extends StatelessWidget {
  const AccountPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final (source, hasCloudKey) = context.select(
      (SettingsService s) => (s.transcriptionSource, s.hasCloudKey),
    );
    final signedIn = context.select((ProfileController p) => p.isAuthenticated);
    final canLeave = source.isCloud ? hasCloudKey : signedIn;

    return AppPanel(
      title: 'Account',
      footer: canLeave ? const AccountExitLink() : null,
      children: [
        const AccountIdentity(),
        switch (source) {
          TranscriptionSource.server => const ServerConnectionSection(),
          TranscriptionSource.groq => const GroqConnectionSection(),
          TranscriptionSource.openRouter => const OpenRouterConnectionSection(),
        },
        const AppInfoSection(),
      ],
    );
  }
}
