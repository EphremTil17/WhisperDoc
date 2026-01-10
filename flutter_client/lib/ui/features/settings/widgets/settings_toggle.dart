import 'package:flutter/material.dart';
import 'package:flutter_client/ui/theme/app_theme.dart';

class SettingsToggle extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  const SettingsToggle({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
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
}
