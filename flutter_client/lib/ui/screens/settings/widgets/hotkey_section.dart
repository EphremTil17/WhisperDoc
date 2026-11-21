import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/hardware/hotkey_service.dart';
import 'package:flutter_client/ui/features/settings/settings.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';

class HotkeySection extends StatelessWidget {
  const HotkeySection({super.key});

  static const double _changeFontSize = 13;

  void _onHotkeySelected(
    BuildContext context,
    String display,
    int mods,
    int vKey,
  ) {
    unawaited(
      context.read<SettingsService>().setHotkey(
        display: display,
        modifiers: mods,
        vKey: vKey,
      ),
    );
  }

  void _showHotkeyRecorder(BuildContext context) {
    final hotkeyService = context.read<HotkeyService>();
    unawaited(hotkeyService.stop());

    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => HotkeyRecorderDialog(
          onSelected: (display, mods, vKey) =>
              _onHotkeySelected(context, display, mods, vKey),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Shortcut', style: AppType.label),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Primary Trigger',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    Text(
                      settings.globalHotkey,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => _showHotkeyRecorder(context),
                child: const Text(
                  'Change',
                  style: TextStyle(
                    color: AppColors.record,
                    fontSize: _changeFontSize,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
