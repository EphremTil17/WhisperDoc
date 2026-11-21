import 'package:flutter_client/controllers/profile_controller.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/account/widgets/account_exit_link.dart';
import 'package:flutter_client/ui/screens/account/widgets/account_identity.dart';
import 'package:flutter_client/ui/screens/account/widgets/app_info_section.dart';
import 'package:flutter_client/ui/screens/account/widgets/groq_connection_section.dart';
import 'package:flutter_client/ui/screens/account/widgets/server_connection_section.dart';
import 'package:flutter_client/ui/shared/widgets/panel/app_panel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Is it working? The service and who is signed in, the connection values,
/// then the app's version and logs for when it is not.
class AccountPanel extends StatelessWidget {
  const AccountPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final isGroqMode = context.select((SettingsService s) => s.isGroqMode);
    final hasGroqKey = context.select(
      (SettingsService s) => s.cachedGroqApiKey?.isNotEmpty ?? false,
    );
    final signedIn = context.select((ProfileController p) => p.isAuthenticated);
    final canLeave = isGroqMode ? hasGroqKey : signedIn;

    return AppPanel(
      title: 'Account',
      footer: canLeave ? const AccountExitLink() : null,
      children: [
        const AccountIdentity(),
        if (isGroqMode)
          const GroqConnectionSection()
        else
          const ServerConnectionSection(),
        const AppInfoSection(),
      ],
    );
  }
}
