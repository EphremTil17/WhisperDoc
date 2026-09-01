import 'package:flutter/material.dart';
import 'package:flutter_client/infrastructure/theme/app_theme.dart';

/// Reusable compact segmented toggle chip with glassmorphic crimson accent styling.
class ModeToggleChip extends StatelessWidget {
  const ModeToggleChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  static const Color _activeChipBackground = Color(0x33DC143C);
  static const Color _activeChipBorder = AppTheme.crimsonPrimary;
  static const Color _activeChipText = AppTheme.crimsonPrimary;
  static const Color _inactiveChipBorder = Colors.white24;
  static const Color _inactiveChipText = Colors.white70;
  static const double _chipFontSize = 9;

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: selected ? _activeChipBackground : Colors.transparent,
            borderRadius: const BorderRadius.all(Radius.circular(6)),
            border: Border.all(
              color: selected ? _activeChipBorder : _inactiveChipBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? _activeChipText : _inactiveChipText,
              fontSize: _chipFontSize,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
