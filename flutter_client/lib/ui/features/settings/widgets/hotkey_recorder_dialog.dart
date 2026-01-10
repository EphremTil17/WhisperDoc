import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_client/core/utils/win32_key_mapper.dart';
import 'package:flutter_client/ui/theme/app_theme.dart';

class HotkeyRecorderDialog extends StatefulWidget {
  final Function(String display, int mods, int vKey) onSelected;

  const HotkeyRecorderDialog({super.key, required this.onSelected});

  @override
  State<HotkeyRecorderDialog> createState() => _HotkeyRecorderDialogState();
}

class _HotkeyRecorderDialogState extends State<HotkeyRecorderDialog> {
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
          final logicalKey = event.logicalKey;
          if (logicalKey != LogicalKeyboardKey.controlLeft &&
              logicalKey != LogicalKeyboardKey.controlRight &&
              logicalKey != LogicalKeyboardKey.altLeft &&
              logicalKey != LogicalKeyboardKey.altRight &&
              logicalKey != LogicalKeyboardKey.shiftLeft &&
              logicalKey != LogicalKeyboardKey.shiftRight) {
            display += logicalKey.keyLabel.toUpperCase();
            vKey = Win32KeyMapper.mapToWin32VKey(logicalKey);
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
}
