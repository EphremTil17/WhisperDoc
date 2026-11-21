import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';

class SettingsToggle extends StatelessWidget {
  const SettingsToggle({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  static const _disabledAlpha = 0.4;

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : _disabledAlpha,
      child: SwitchListTile(
        title: Text(title, style: AppType.body),
        subtitle: Text(
          subtitle,
          style: AppType.caption.copyWith(color: AppColors.textMuted),
        ),
        value: value,
        onChanged: enabled ? onChanged : null,
        contentPadding: EdgeInsets.zero,
        dense: true,
      ),
    );
  }
}
