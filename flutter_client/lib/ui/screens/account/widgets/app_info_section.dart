import 'dart:async';

import 'package:flutter_client/controllers/profile_controller.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/utility/update_service.dart';
import 'package:flutter_client/ui/screens/logs_panel.dart';
import 'package:flutter_client/ui/shared/widgets/app_button.dart';
import 'package:flutter_client/ui/shared/widgets/panel/app_panel.dart';
import 'package:flutter_client/ui/shared/widgets/panel/panel_row.dart';
import 'package:flutter_client/ui/shared/widgets/panel/panel_section.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// The app itself: this version and whether a newer one exists (amber only
/// when an update is waiting, alert when the server needs one), and the logs
/// for when something is wrong.
class AppInfoSection extends StatelessWidget {
  const AppInfoSection({super.key});

  static void _open(String url) {
    final target = UpdateService.isTrustedReleaseUrl(url)
        ? url
        : AppConstants.updateUrl;
    unawaited(
      launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication),
    );
  }

  @override
  Widget build(BuildContext context) {
    final version = context.select((SettingsService s) => s.appVersion);
    final profile = context.watch<ProfileController>();
    final latest = profile.latestVersion;
    final download = profile.latestDownloadUrl ?? AppConstants.updateUrl;
    final current = profile.updateStatus == UpdateStatus.upToDate;

    final (
      IconData icon,
      Color tone,
      String note,
    ) = switch (profile.updateStatus) {
      UpdateStatus.upToDate => (
        AppIcons.circleCheck,
        AppColors.textMuted,
        'Up to date',
      ),
      UpdateStatus.advisory => (
        AppIcons.download,
        AppColors.update,
        latest == null ? 'A new version is available' : '$latest is available',
      ),
      UpdateStatus.required => (
        AppIcons.circleAlert,
        AppColors.alert,
        'Your server needs a newer version',
      ),
    };

    return PanelSection(
      label: 'App',
      children: [
        PanelRow(
          icon: icon,
          iconColor: tone,
          label: 'Version $version',
          subtitle: note,
          subtitleColor: tone,
          value: current ? 'Release notes' : null,
          onTap: current ? () => _open(AppConstants.updateUrl) : null,
          trailing: current
              ? null
              : AppButton(label: 'Update', onPressed: () => _open(download)),
        ),
        PanelRow(
          icon: AppIcons.fileText,
          label: 'Logs',
          value: 'For troubleshooting',
          rule: false,
          onTap: () =>
              unawaited(AppPanel.push<void>(context, const LogsPanel())),
        ),
      ],
    );
  }
}
