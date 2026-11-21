import 'dart:async';

import 'package:flutter_client/controllers/recording_controller.dart';
import 'package:flutter_client/infrastructure/theme/app_icons.dart';
import 'package:flutter_client/services/hardware/hotkey_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/settings/widgets/hotkey_recorder_dialog.dart';
import 'package:flutter_client/ui/shared/widgets/keycap.dart';
import 'package:flutter_client/ui/shared/widgets/panel/panel_row.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

/// The global shortcut on a keycap; tapping records a new one.
class ShortcutRow extends StatelessWidget {
  const ShortcutRow({super.key});

  /// The live hotkey is released while recording, so pressing the current
  /// shortcut is captured instead of starting a dictation. A new binding is
  /// re-registered by the home screen's settings listener; otherwise the old
  /// one is restored here.
  static Future<void> _record(BuildContext context) async {
    final hotkeys = context.read<HotkeyService>();
    final settings = context.read<SettingsService>();
    await hotkeys.stop();
    if (!context.mounted) return hotkeys.resume();

    final picked = await showDialog<HotkeyBinding>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const HotkeyRecorderDialog(),
    );
    final changed =
        picked != null &&
        (picked.modifiers != settings.hotkeyModifiers ||
            picked.vKey != settings.hotkeyVKey);
    if (!changed) return hotkeys.resume();

    await settings.setHotkey(
      display: picked.display,
      modifiers: picked.modifiers,
      vKey: picked.vKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hotkey = context.select((SettingsService s) => s.globalHotkey);
    final recording = context.select((RecordingController c) => c.isRecording);

    return PanelRow(
      icon: AppIcons.keyboard,
      label: 'Shortcut',
      subtitle: recording ? 'Stop recording to change' : null,
      trailing: Keycap(hotkey.replaceAll('+', ' ')),
      chevron: true,
      enabled: !recording,
      onTap: () => unawaited(_record(context)),
    );
  }
}
