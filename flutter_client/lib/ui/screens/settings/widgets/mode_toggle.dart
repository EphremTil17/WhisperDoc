import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/ui/screens/settings/widgets/mode_toggle_chip.dart';

class ModeToggle extends StatelessWidget {
  const ModeToggle({
    super.key,
    required this.isGroqMode,
    required this.enabled,
    required this.settings,
  });

  static const double _disabledOpacity = 0.4;

  final bool isGroqMode;
  final bool enabled;
  final SettingsService settings;

  void _selectBackendMode() {
    unawaited(settings.setTranscriptionMode('backend'));
  }

  void _selectGroqMode() {
    unawaited(settings.setTranscriptionMode('groq'));
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : _disabledOpacity,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ModeToggleChip(
            label: 'WhisperDoc',
            selected: !isGroqMode,
            onTap: enabled ? _selectBackendMode : null,
          ),
          const SizedBox(width: 4),
          ModeToggleChip(
            label: 'Groq Cloud',
            selected: isGroqMode,
            onTap: enabled ? _selectGroqMode : null,
          ),
        ],
      ),
    );
  }
}
