import 'package:flutter_client/ui/shared/widgets/panel/panel_row.dart';
import 'package:material_ui/material_ui.dart';

/// A panel row that is a switch; tapping anywhere on the row flips it.
class PanelToggleRow extends StatelessWidget {
  const PanelToggleRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
    this.rule = true,
  });

  /// The switch drawn at 40×24 so toggle rows keep the 48px row height.
  static const Size _switchSize = Size(40, 24);

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Why the row is disabled, or what it does.
  final String? subtitle;
  final bool enabled;

  /// Draws the rule beneath; off for a panel's last row.
  final bool rule;

  @override
  Widget build(BuildContext context) {
    // One announcement: the label with its on/off state.
    return MergeSemantics(
      child: PanelRow(
        icon: icon,
        label: label,
        subtitle: subtitle,
        enabled: enabled,
        rule: rule,
        onTap: () => onChanged(!value),
        trailing: ExcludeFocus(
          // The row takes focus and taps; the switch only shows the state.
          child: SizedBox.fromSize(
            size: _switchSize,
            child: FittedBox(
              child: Switch(
                value: value,
                onChanged: enabled ? onChanged : null,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
