import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_client/infrastructure/utils/win32_key_mapper.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';

class HotkeyRecorderDialog extends StatefulWidget {
  const HotkeyRecorderDialog({super.key, required this.onSelected});

  final Function(String display, int mods, int vKey) onSelected;

  @override
  State<HotkeyRecorderDialog> createState() => _HotkeyRecorderDialogState();
}

class _HotkeyRecorderDialogState extends State<HotkeyRecorderDialog> {
  static const _modControl = 0x0002;
  static const _modAlt = 0x0001;
  static const _modShift = 0x0004;
  static const _borderAlpha = 0.3;

  FocusNode? _focusNode;
  String _currentKeys = 'Press keys...';
  int _mods = 0;
  int _vKey = 0;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode?.requestFocus();
      }
    });
  }

  void _onKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      String display = '';
      int mods = 0;
      int? vKey;

      if (HardwareKeyboard.instance.isControlPressed) {
        display += 'Ctrl+';
        mods |= _modControl;
      }
      if (HardwareKeyboard.instance.isAltPressed) {
        display += 'Alt+';
        mods |= _modAlt;
      }
      if (HardwareKeyboard.instance.isShiftPressed) {
        display += 'Shift+';
        mods |= _modShift;
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

      final resolvedVKey = vKey;
      if (resolvedVKey != null && mods != 0) {
        setState(() {
          _currentKeys = display;
          _mods = mods;
          _vKey = resolvedVKey;
        });
      }
    }
  }

  void _handleSave() {
    widget.onSelected(_currentKeys, _mods, _vKey);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _focusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focusNode = _focusNode;
    if (focusNode == null) return const SizedBox.shrink();

    return KeyboardListener(
      focusNode: focusNode,
      onKeyEvent: _onKeyEvent,
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
                borderRadius: const BorderRadius.all(Radius.circular(12)),
                border: Border.all(
                  color: AppTheme.crimsonPrimary.withValues(
                    alpha: _borderAlpha,
                  ),
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
            onPressed: _vKey != 0 ? _handleSave : null,
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
