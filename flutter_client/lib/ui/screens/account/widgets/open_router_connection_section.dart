import 'dart:async';

import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/formatters/secret_mask.dart';
import 'package:flutter_client/logic/models/model_selection_problem.dart';
import 'package:flutter_client/services/transcription/open_router_catalog.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/account/account_fields.dart';
import 'package:flutter_client/ui/shared/widgets/confirm_dialog.dart';
import 'package:flutter_client/ui/shared/widgets/panel/panel_row.dart';
import 'package:flutter_client/ui/shared/widgets/panel/panel_section.dart';
import 'package:flutter_client/ui/shared/widgets/panel/panel_toggle_row.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// OpenRouter connection: key, speech and rewrite models, zero data
/// retention, language.
class OpenRouterConnectionSection extends StatelessWidget {
  const OpenRouterConnectionSection({super.key});

  /// Letting hosts keep audio is a privacy decision, so it is asked, not
  /// toggled; keeping zero data needs no confirmation.
  static Future<void> _setZdr(BuildContext context, bool on) async {
    final settings = context.read<SettingsService>();
    final confirmed =
        on ||
        await ConfirmDialog.ask(
          context,
          title: 'Allow hosts that keep data?',
          message:
              'Some hosts may store your audio and text for a while. '
              'More models become available.',
          confirmLabel: 'Allow',
        );
    if (confirmed) await settings.setOpenRouterZdr(on);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final catalog = context.watch<OpenRouterCatalog>();
    final key = SecretMask.of(settings.cachedOpenRouterApiKey);
    // The key is used for the upload after you stop; the rest may change
    // until then and apply to this clip.
    final locked = context.select((RecordingController c) => c.isSessionActive);
    final model = catalog.find(settings.openRouterModel);
    final problem = catalog.selectionProblem;
    final (String modelValue, bool modelAlert) = switch (problem) {
      ModelSelectionProblem.none => (
        model?.name ?? settings.openRouterModel ?? '',
        false,
      ),
      ModelSelectionProblem.notChosen => (
        catalog.isRefreshing ? 'Loading…' : 'Choose',
        !catalog.isRefreshing,
      ),
      ModelSelectionProblem.retired => ('Retired', true),
      ModelSelectionProblem.retainsData => ('Keeps data', true),
    };

    return PanelSection(
      label: 'Connection',
      children: [
        PanelRow(
          icon: AppIcons.keyRound,
          iconColor: key.isEmpty ? AppColors.alert : null,
          label: 'API key',
          subtitle: locked ? PanelRow.lockedWhileRecording : null,
          value: key.isEmpty ? 'Not set' : key,
          valueColor: key.isEmpty ? AppColors.alert : null,
          enabled: !locked,
          onTap: () => unawaited(AccountFields.openRouterKey(context)),
        ),
        PanelRow(
          icon: AppIcons.cpu,
          iconColor: modelAlert ? AppColors.alert : null,
          label: 'Model',
          value: modelValue,
          valueColor: modelAlert ? AppColors.alert : null,
          enabled: key.isNotEmpty,
          onTap: () => unawaited(AccountFields.openRouterModel(context)),
        ),
        PanelRow(
          icon: AppIcons.sparkles,
          label: 'Rewrite model',
          subtitle: 'For output styles',
          value: settings.hasCustomRewriteModel
              ? settings.openRouterRewriteModel.split('/').last
              : AppConstants.openRouterTransformModelName,
          enabled: key.isNotEmpty,
          onTap: () => unawaited(AccountFields.openRouterRewriteModel(context)),
        ),

        PanelToggleRow(
          icon: AppIcons.shieldCheck,
          label: 'Zero data retention',
          subtitle: settings.openRouterZdr
              ? 'Only hosts that keep nothing'
              : 'Hosts may keep your audio',
          value: settings.openRouterZdr,
          onChanged: (on) => unawaited(_setZdr(context, on)),
        ),
        PanelRow(
          icon: AppIcons.globe,
          label: 'Language',
          value: AccountFields.languageName(settings.openRouterLanguage),
          onTap: () => unawaited(AccountFields.openRouterLanguage(context)),
        ),
      ],
    );
  }
}
