import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/hardware/hotkey_service.dart';
import 'package:flutter_client/ui/features/settings/settings.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';

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
        const Text(
          'HOTKEY',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
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
                child: Text(
                  'Change',
                  style: TextStyle(
                    fontFamily: GoogleFonts.lexend().fontFamily,
                    color: AppTheme.crimsonPrimary,
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
