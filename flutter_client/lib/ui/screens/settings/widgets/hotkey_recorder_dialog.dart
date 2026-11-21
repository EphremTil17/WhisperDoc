import 'package:flutter/services.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';
import 'package:flutter_client/infrastructure/utils/win32_key_mapper.dart';
import 'package:flutter_client/ui/shared/widgets/app_button.dart';
import 'package:flutter_client/ui/shared/widgets/app_dialog.dart';
import 'package:flutter_client/ui/shared/widgets/caption_cue.dart';
import 'package:flutter_client/ui/shared/widgets/crisp_text.dart';
import 'package:flutter_client/ui/shared/widgets/keycap.dart';
import 'package:material_ui/material_ui.dart';

/// A global shortcut: its label (`Ctrl+Q`) and the Win32 binding.
typedef HotkeyBinding = ({String display, int modifiers, int vKey});

/// Records a new global shortcut: at least one modifier plus a key. Pops the
/// [HotkeyBinding] on Save, or nothing on Cancel.
class HotkeyRecorderDialog extends StatefulWidget {
  const HotkeyRecorderDialog({super.key});

  @override
  State<HotkeyRecorderDialog> createState() => _HotkeyRecorderDialogState();
}

class _HotkeyRecorderDialogState extends State<HotkeyRecorderDialog> {
  // Win32 RegisterHotKey modifier flags.
  static const int _modAlt = 0x0001;
  static const int _modControl = 0x0002;
  static const int _modShift = 0x0004;
  static const double _maxWidth = 360;

  static final Set<LogicalKeyboardKey> _modifierKeys = {
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
  };

  final FocusNode _focus = FocusNode();
  HotkeyBinding? _binding;

  void _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || _modifierKeys.contains(event.logicalKey)) {
      return;
    }
    final vKey = Win32KeyMapper.mapToWin32VKey(event.logicalKey);
    final keyboard = HardwareKeyboard.instance;
    final held = [
      if (keyboard.isControlPressed) ('Ctrl', _modControl),
      if (keyboard.isAltPressed) ('Alt', _modAlt),
      if (keyboard.isShiftPressed) ('Shift', _modShift),
    ];
    // A bare key would swallow normal typing system-wide.
    if (vKey == null || held.isEmpty) return;

    setState(() {
      _binding = (
        display: [
          for (final (name, _) in held) name,
          event.logicalKey.keyLabel.toUpperCase(),
        ].join('+'),
        modifiers: held.fold(0, (mods, m) => mods | m.$2),
        vKey: vKey,
      );
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final binding = _binding;

    return KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: AppDialog(
        title: 'Shortcut',
        shrinkWrap: true,
        maxWidth: _maxWidth,
        body: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: AppSpace.xl,
            children: [
              CrispText(
                'Hold Ctrl, Alt or Shift, then press a key.',
                textAlign: TextAlign.center,
                style: AppType.body.copyWith(color: AppColors.textMuted),
              ),
              if (binding == null)
                const CaptionCue('waiting for keys')
              else
                Keycap(binding.display.replaceAll('+', ' '), style: AppType.title),
            ],
          ),
        ),
        footer: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          spacing: AppSpace.sm,
          children: [
            AppButton(
              label: 'Cancel',
              tone: AppButtonTone.outline,
              onPressed: () => Navigator.of(context).pop(),
            ),
            AppButton(
              label: 'Save',
              onPressed: binding == null
                  ? null
                  : () => Navigator.of(context).pop(binding),
            ),
          ],
        ),
      ),
    );
  }
}
