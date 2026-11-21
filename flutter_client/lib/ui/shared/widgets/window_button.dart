import 'package:material_ui/material_ui.dart';
import 'package:flutter_client/infrastructure/theme/app_tokens.dart';

/// Minimize/close: the themed icon button, sized for the title bar, with a
/// crimson hover on close (the only place the window itself turns red).
class WindowButton extends StatelessWidget {
  const WindowButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isClose = false,
  });

  static const Size _size = Size(AppSizes.iconButton, 32);
  static const double _iconSize = 14;

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isClose;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: _iconSize),
      style: IconButton.styleFrom(
        fixedSize: _size,
        hoverColor: isClose ? AppColors.record : AppColors.band,
      ).copyWith(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.hovered)
              ? AppColors.text
              : AppColors.textMuted,
        ),
      ),
    );
  }
}
