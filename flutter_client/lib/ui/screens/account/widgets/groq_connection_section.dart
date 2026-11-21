import 'dart:async';

import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/logic/formatters/secret_mask.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/account/account_fields.dart';
import 'package:flutter_client/ui/shared/widgets/panel/panel_row.dart';
import 'package:flutter_client/ui/shared/widgets/panel/panel_section.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// Groq Cloud connection: key, model, language and words to expect.
class GroqConnectionSection extends StatelessWidget {
  const GroqConnectionSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final key = SecretMask.of(settings.cachedGroqApiKey);

    return PanelSection(
      label: 'Connection',
      children: [
        PanelRow(
          icon: AppIcons.keyRound,
          iconColor: key.isEmpty ? AppColors.alert : null,
          label: 'API key',
          value: key.isEmpty ? 'Not set' : key,
          valueColor: key.isEmpty ? AppColors.alert : null,
          onTap: () => unawaited(AccountFields.groqKey(context)),
        ),
        PanelRow(
          icon: AppIcons.cpu,
          label: 'Model',
          value:
              AppConstants.groqModelDisplayNames[settings.groqModel] ??
              settings.groqModel,
          onTap: () => unawaited(AccountFields.groqModel(context)),
        ),
        PanelRow(
          icon: AppIcons.globe,
          label: 'Language',
          value: AccountFields.languageName(settings.groqLanguage),
          onTap: () => unawaited(AccountFields.groqLanguage(context)),
        ),
        PanelRow(
          icon: AppIcons.textCursorInput,
          label: 'Words to expect',
          value: settings.groqPrompt.isEmpty ? 'None' : 'Set',
          onTap: () => unawaited(AccountFields.groqPrompt(context)),
        ),
      ],
    );
  }
}
