import 'dart:async';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:flutter_client/core/services/settings_service.dart';
import 'package:flutter_client/core/services/websocket_service.dart';
import 'package:flutter_client/core/services/hotkey_service.dart';
import 'package:flutter_client/ui/features/settings/settings.dart';
import 'package:flutter_client/ui/shared/widgets/glass_dialog.dart';
import 'package:flutter_client/ui/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _uriController;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsService>();
    _uriController = TextEditingController(text: settings.serverUri);
  }

  @override
  void dispose() {
    _uriController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings() async {
    final settings = context.read<SettingsService>();
    await settings.setServerUri(_uriController.text);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();

    return GlassDialog(
      title: 'Settings',
      shrinkWrap: true,
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.data?.version ?? '...';
              return Text(
                'v$version',
                style: const TextStyle(color: Colors.white24, fontSize: 12),
              );
            },
          ),
          TextButton(
            onPressed: _saveSettings,
            child: Text(
              'Done',
              style: TextStyle(
                fontFamily: GoogleFonts.lexend().fontFamily,
                color: AppTheme.crimsonPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Connection Section
            const Text(
              'CONNECTION',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Server URI',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _uriController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                hintText: 'ws://localhost:9989/ws',
                hintStyle: const TextStyle(color: Colors.white24),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Test Connection Button
            Consumer<WebSocketService>(
              builder: (context, wsService, child) {
                final status = wsService.status;
                Color btnColor = Colors.white10;
                String btnText = 'Test Connection';

                if (status == ConnectionStatus.connected) {
                  btnColor = Colors.green.withValues(alpha: 0.2);
                  btnText = 'Connected';
                } else if (status == ConnectionStatus.connecting) {
                  btnText = 'Connecting...';
                }

                return FilledButton(
                  onPressed: () async {
                    // Update settings first to trigger reconnect
                    await context.read<SettingsService>().setServerUri(
                      _uriController.text,
                    );
                    // The WebSocketService listens to this and will auto-reconnect
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: btnColor,
                    foregroundColor: status == ConnectionStatus.connected
                        ? Colors.greenAccent
                        : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(btnText),
                );
              },
            ),

            const SizedBox(height: 16),

            // Hotkey Section
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
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
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
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Automation Section
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

            // Auto-Copy Toggle
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
        ),
      ),
    );
  }

  void _showHotkeyRecorder(BuildContext context) {
    final hotkeyService = context.read<HotkeyService>();
    // Stop the global hotkey so it doesn't interfere with recording
    unawaited(hotkeyService.stop());

    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => HotkeyRecorderDialog(
          onSelected: (display, mods, vKey) {
            unawaited(
              context.read<SettingsService>().setHotkey(
                display: display,
                modifiers: mods,
                vKey: vKey,
              ),
            );
          },
        ),
      ).then((_) {
        // HomeScreen's settings listener will restart the service automatically
        // when SettingsService.setHotkey() is called. No need to call start() here.
      }),
    );
  }
}
