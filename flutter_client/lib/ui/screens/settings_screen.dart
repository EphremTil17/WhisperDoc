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
import 'package:flutter_client/core/services/handshake_state_machine.dart';
import 'package:flutter_client/core/services/jwt_validator.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _uriController;
  final JWTValidator _jwtValidator = JWTValidator();

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

            // Authentication Section (Phase 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'API KEY',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color:
                        settings
                            .getTokenLabel(settings.cachedApiKey ?? '')
                            .contains('JWT')
                        ? Colors.blue.withValues(alpha: 0.2)
                        : Colors.purple.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color:
                          settings
                              .getTokenLabel(settings.cachedApiKey ?? '')
                              .contains('JWT')
                          ? Colors.blue.withValues(alpha: 0.5)
                          : Colors.purple.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    settings.getTokenLabel(settings.cachedApiKey ?? ''),
                    style: TextStyle(
                      color:
                          settings
                              .getTokenLabel(settings.cachedApiKey ?? '')
                              .contains('JWT')
                          ? Colors.blueAccent
                          : Colors.purpleAccent,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // JWT Expiry Warning (if applicable)
            if (settings.cachedApiKey != null &&
                settings.cachedApiKey!.isNotEmpty)
              Builder(
                builder: (context) {
                  final warning = _jwtValidator.getExpiryWarning(
                    settings.cachedApiKey!,
                  );
                  if (warning == null) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.orange.withValues(alpha: 0.15),
                            Colors.orange.withValues(alpha: 0.05),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.orangeAccent.withValues(alpha: 0.3),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.access_time,
                            color: Colors.orangeAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              warning,
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

            _SecureApiKeyField(
              initialValue: settings.cachedApiKey ?? '',
              onChanged: (val) => settings.setApiKey(val),
            ),
            const SizedBox(height: 16),

            // Test Connection Button
            Consumer<WebSocketService>(
              builder: (context, wsService, child) {
                final status = wsService.status;
                final handshake = wsService.handshakeState.state;

                Color btnColor = Colors.white10;
                Color textColor = Colors.white;
                String btnText = 'Test Connection';

                if (handshake == HandshakeState.authenticated) {
                  btnColor = Colors.green.withValues(alpha: 0.2);
                  textColor = Colors.greenAccent;
                  btnText = 'Authenticated ✓';
                } else if (handshake == HandshakeState.authenticating ||
                    status == ConnectionStatus.connecting) {
                  btnText = 'Connecting...';
                } else if (handshake == HandshakeState.failed) {
                  btnColor = Colors.red.withValues(alpha: 0.2);
                  textColor = Colors.redAccent;
                  btnText = 'Failed ✗';
                } else if (status == ConnectionStatus.connected) {
                  // Fallback for when connected but handshake state is somehow not authenticated
                  btnColor = Colors.green.withValues(alpha: 0.2);
                  textColor = Colors.greenAccent;
                  btnText = 'Connected';
                }

                return FilledButton(
                  onPressed: () async {
                    // Update settings first to trigger reconnect
                    await context.read<SettingsService>().setServerUri(
                      _uriController.text,
                    );
                    // Explicitly call connect if not already connecting
                    if (status != ConnectionStatus.connecting) {
                      unawaited(wsService.connect());
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: btnColor,
                    foregroundColor: textColor,
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

/// Helper widget for secure API key entry with visibility toggle.
class _SecureApiKeyField extends StatefulWidget {
  final String initialValue;
  final ValueChanged<String> onChanged;

  const _SecureApiKeyField({
    required this.initialValue,
    required this.onChanged,
  });

  @override
  State<_SecureApiKeyField> createState() => _SecureApiKeyFieldState();
}

class _SecureApiKeyFieldState extends State<_SecureApiKeyField> {
  late TextEditingController _controller;
  bool _obscureText = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      obscureText: _obscureText,
      maxLines: _obscureText ? 1 : null, // Only wrap when visible
      keyboardType: TextInputType.multiline,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.black26,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        hintText: 'Enter your API key or JWT token',
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            _obscureText ? Icons.visibility_off : Icons.visibility,
            color: Colors.white38,
            size: 18,
          ),
          onPressed: () => setState(() => _obscureText = !_obscureText),
        ),
      ),
    );
  }
}
