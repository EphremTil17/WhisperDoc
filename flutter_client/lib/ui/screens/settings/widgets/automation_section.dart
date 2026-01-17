import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/services/settings_service.dart';
import 'package:flutter_client/ui/features/settings/settings.dart';

class AutomationSection extends StatelessWidget {
  const AutomationSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'AUTOMATION',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 12),
        SettingsToggle(
          title: 'Auto Copy',
          subtitle: 'Copy text to clipboard after recording',
          value: settings.autoCopy,
          onChanged: (val) => settings.setAutoCopy(val),
        ),
        const SizedBox(height: 8),
        SettingsToggle(
          title: 'Auto Paste',
          subtitle: 'Paste text automatically after copying',
          value: settings.autoPaste,
          onChanged: (val) => settings.setAutoPaste(val),
          enabled: settings.autoCopy,
        ),
        const SizedBox(height: 8),
        SettingsToggle(
          title: 'Show Visualizer',
          subtitle: 'Display audio waveform during recording',
          value: settings.showVisualizer,
          onChanged: (val) => settings.setShowVisualizer(val),
        ),
      ],
    );
  }
}
