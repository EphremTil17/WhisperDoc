import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_client/core/services/settings_service.dart';
import 'package:flutter_client/core/services/websocket_service.dart';
import 'package:flutter_client/core/services/hotkey_service.dart';
import 'package:flutter_client/ui/components/glass_container.dart';
import 'package:flutter_client/ui/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

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

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: GlassContainer(
        opacity: 0.15,
        blur: 20,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Settings',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(color: Colors.white10),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
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
                            foregroundColor:
                                status == ConnectionStatus.connected
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
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
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                  ),
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
                    _buildToggle(
                      context: context,
                      title: 'Auto-Copy',
                      subtitle: 'Sync transcription to clipboard',
                      value: settings.autoCopy,
                      onChanged: (val) => settings.setAutoCopy(val),
                    ),

                    const SizedBox(height: 8),

                    // Auto-Paste Toggle
                    _buildToggle(
                      context: context,
                      title: 'Auto-Paste',
                      subtitle: 'Simulate Ctrl+V after transcription',
                      value: settings.autoPaste,
                      enabled: settings.autoCopy,
                      onChanged: (val) => settings.setAutoPaste(val),
                    ),

                    const SizedBox(height: 16),

                    // Footer
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'v1.5.0',
                          style: TextStyle(color: Colors.white24, fontSize: 12),
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggle({
    required BuildContext context,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(fontSize: 14)),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 11, color: Colors.white38),
        ),
        value: value,
        onChanged: enabled ? onChanged : null,
        activeThumbColor: AppTheme.crimsonPrimary,
        contentPadding: EdgeInsets.zero,
        dense: true,
      ),
    );
  }

  void _showHotkeyRecorder(BuildContext context) {
    final hotkeyService = context.read<HotkeyService>();
    unawaited(hotkeyService.unregisterHotkey(1));

    unawaited(
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => _HotkeyRecorderDialog(
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
        if (!context.mounted) return;
        final settings = context.read<SettingsService>();
        unawaited(
          hotkeyService.registerHotkey(
            id: 1,
            modifiers: settings.hotkeyModifiers,
            vKey: settings.hotkeyVKey,
          ),
        );
      }),
    );
  }
}

class _HotkeyRecorderDialog extends StatefulWidget {
  final Function(String display, int mods, int vKey) onSelected;

  const _HotkeyRecorderDialog({required this.onSelected});

  @override
  State<_HotkeyRecorderDialog> createState() => _HotkeyRecorderDialogState();
}

class _HotkeyRecorderDialogState extends State<_HotkeyRecorderDialog> {
  String _currentKeys = 'Press keys...';
  int _mods = 0;
  int _vKey = 0;

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          String display = '';
          int mods = 0;
          int? vKey;

          if (HardwareKeyboard.instance.isControlPressed) {
            display += 'Ctrl+';
            mods |= 0x0002; // MOD_CONTROL
          }
          if (HardwareKeyboard.instance.isAltPressed) {
            display += 'Alt+';
            mods |= 0x0001; // MOD_ALT
          }
          if (HardwareKeyboard.instance.isShiftPressed) {
            display += 'Shift+';
            mods |= 0x0004; // MOD_SHIFT
          }

          // Map physical to Win32 virtual key (approximate for common keys)
          // For now, use a simple mapping or just the label if it's not a mod
          final logicalKey = event.logicalKey;
          if (logicalKey != LogicalKeyboardKey.controlLeft &&
              logicalKey != LogicalKeyboardKey.controlRight &&
              logicalKey != LogicalKeyboardKey.altLeft &&
              logicalKey != LogicalKeyboardKey.altRight &&
              logicalKey != LogicalKeyboardKey.shiftLeft &&
              logicalKey != LogicalKeyboardKey.shiftRight) {
            display += logicalKey.keyLabel.toUpperCase();
            vKey = _mapToWin32VKey(logicalKey);
          }

          if (vKey != null && mods != 0) {
            setState(() {
              _currentKeys = display;
              _mods = mods;
              _vKey = vKey!;
            });
          }
        }
      },
      child: AlertDialog(
        backgroundColor: const Color(0xFF1A1A1E),
        title: const Text(
          'Record Hotkey',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Hold your desired key combination',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black38,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.crimsonPrimary.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                _currentKeys,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          FilledButton(
            onPressed: _vKey != 0
                ? () {
                    widget.onSelected(_currentKeys, _mods, _vKey);
                    Navigator.pop(context);
                  }
                : null,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.crimsonPrimary,
            ),
            child: const Text('Save Hotkey'),
          ),
        ],
      ),
    );
  }

  int? _mapToWin32VKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.keyA) {
      return 0x41;
    }
    if (key == LogicalKeyboardKey.keyB) {
      return 0x42;
    }
    if (key == LogicalKeyboardKey.keyC) {
      return 0x43;
    }
    if (key == LogicalKeyboardKey.keyD) {
      return 0x44;
    }
    if (key == LogicalKeyboardKey.keyE) {
      return 0x45;
    }
    if (key == LogicalKeyboardKey.keyF) {
      return 0x46;
    }
    if (key == LogicalKeyboardKey.keyG) {
      return 0x47;
    }
    if (key == LogicalKeyboardKey.keyH) {
      return 0x48;
    }
    if (key == LogicalKeyboardKey.keyI) {
      return 0x49;
    }
    if (key == LogicalKeyboardKey.keyJ) {
      return 0x4A;
    }
    if (key == LogicalKeyboardKey.keyK) {
      return 0x4B;
    }
    if (key == LogicalKeyboardKey.keyL) {
      return 0x4C;
    }
    if (key == LogicalKeyboardKey.keyM) {
      return 0x4D;
    }
    if (key == LogicalKeyboardKey.keyN) {
      return 0x4E;
    }
    if (key == LogicalKeyboardKey.keyO) {
      return 0x4F;
    }
    if (key == LogicalKeyboardKey.keyP) {
      return 0x50;
    }
    if (key == LogicalKeyboardKey.keyQ) {
      return 0x51;
    }
    if (key == LogicalKeyboardKey.keyR) {
      return 0x52;
    }
    if (key == LogicalKeyboardKey.keyS) {
      return 0x53;
    }
    if (key == LogicalKeyboardKey.keyT) {
      return 0x54;
    }
    if (key == LogicalKeyboardKey.keyU) {
      return 0x55;
    }
    if (key == LogicalKeyboardKey.keyV) {
      return 0x56;
    }
    if (key == LogicalKeyboardKey.keyW) {
      return 0x57;
    }
    if (key == LogicalKeyboardKey.keyX) {
      return 0x58;
    }
    if (key == LogicalKeyboardKey.keyY) {
      return 0x59;
    }
    if (key == LogicalKeyboardKey.keyZ) {
      return 0x5A;
    }

    if (key == LogicalKeyboardKey.f1) {
      return 0x70;
    }
    if (key == LogicalKeyboardKey.f2) {
      return 0x71;
    }
    if (key == LogicalKeyboardKey.f3) {
      return 0x72;
    }
    if (key == LogicalKeyboardKey.f4) {
      return 0x73;
    }
    if (key == LogicalKeyboardKey.f5) {
      return 0x74;
    }
    if (key == LogicalKeyboardKey.f6) {
      return 0x75;
    }
    if (key == LogicalKeyboardKey.f7) {
      return 0x76;
    }
    if (key == LogicalKeyboardKey.f8) {
      return 0x77;
    }
    if (key == LogicalKeyboardKey.f9) {
      return 0x78;
    }
    if (key == LogicalKeyboardKey.f10) {
      return 0x79;
    }
    if (key == LogicalKeyboardKey.f11) {
      return 0x7A;
    }
    if (key == LogicalKeyboardKey.f12) {
      return 0x7B;
    }

    return null;
  }
}
