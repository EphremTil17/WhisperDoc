import 'dart:async';

import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/settings/widgets/microphone_panel.dart';
import 'package:flutter_client/ui/screens/settings/widgets/shortcut_row.dart';
import 'package:flutter_client/ui/shared/widgets/panel/app_panel.dart';
import 'package:flutter_client/ui/shared/widgets/panel/panel_row.dart';
import 'package:flutter_client/ui/shared/widgets/panel/panel_section.dart';
import 'package:flutter_client/ui/shared/widgets/panel/panel_toggle_row.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// How the app behaves: what it listens with, the shortcut, what happens to
/// the text when you stop, and whether the background moves. Every change
/// applies at once.
class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final recording = context.select((RecordingController c) => c.isRecording);
    final microphone = settings.microphoneId == null
        ? 'System default'
        : settings.microphoneLabel ?? 'Chosen device';

    return AppPanel(
      title: 'Settings',
      children: [
        PanelSection(
          label: 'Recording',
          children: [
            PanelRow(
              icon: AppIcons.mic,
              label: 'Microphone',
              value: microphone,
              subtitle: recording ? 'Stop recording to change' : null,
              enabled: !recording,
              onTap: () => unawaited(
                AppPanel.push<void>(context, const MicrophonePanel()),
              ),
            ),
            const ShortcutRow(),
            PanelToggleRow(
              icon: AppIcons.audioLines,
              label: 'Show level meter',
              value: settings.showVisualizer,
              onChanged: (on) => unawaited(settings.setShowVisualizer(on)),
            ),
          ],
        ),
        PanelSection(
          label: 'When you stop',
          children: [
            PanelToggleRow(
              icon: AppIcons.clipboard,
              label: 'Copy to clipboard',
              value: settings.autoCopy,
              onChanged: (on) => unawaited(settings.setAutoCopy(on)),
            ),
            PanelToggleRow(
              icon: AppIcons.arrowRightToLine,
              label: 'Paste where your cursor is',
              subtitle: settings.autoCopy ? null : 'Needs Copy to clipboard',
              value: settings.autoCopy && settings.autoPaste,
              enabled: settings.autoCopy,
              onChanged: (on) => unawaited(settings.setAutoPaste(on)),
            ),
          ],
        ),
        PanelSection(
          label: 'Appearance',
          children: [
            PanelToggleRow(
              icon: AppIcons.mountain,
              label: 'Moving background',
              subtitle: 'Off keeps a still map, for slower computers',
              value: settings.animateBackground,
              rule: false,
              onChanged: (on) => unawaited(settings.setAnimateBackground(on)),
            ),
          ],
        ),
      ],
    );
  }
}
