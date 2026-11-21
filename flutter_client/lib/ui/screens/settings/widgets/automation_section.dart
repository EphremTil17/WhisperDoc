import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/features/settings/settings.dart';

class AutomationSection extends StatelessWidget {
  const AutomationSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('When you stop', style: AppType.label),
        const SizedBox(height: 12),
        SettingsToggle(
          title: 'Copy to clipboard',
          subtitle: 'Your text is ready to paste anywhere',
          value: settings.autoCopy,
          onChanged: (val) => settings.setAutoCopy(val),
        ),
        const SizedBox(height: 8),
        SettingsToggle(
          title: 'Paste where your cursor is',
          subtitle: 'Types it into the app you were using',
          value: settings.autoPaste,
          onChanged: (val) => settings.setAutoPaste(val),
          enabled: settings.autoCopy,
        ),
        const SizedBox(height: 8),
        SettingsToggle(
          title: 'Show level meter',
          subtitle: 'The pixel meter while you record',
          value: settings.showVisualizer,
          onChanged: (val) => settings.setShowVisualizer(val),
        ),
      ],
    );
  }
}
