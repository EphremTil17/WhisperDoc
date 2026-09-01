import 'package:flutter/material.dart';

/// The bottom action tile in the profile dropdown for creating a new custom dictation profile.
class AddCustomProfileTile extends StatefulWidget {
  const AddCustomProfileTile({required this.onTap, super.key});

  final VoidCallback onTap;

  static const double _tileHoverBgAlpha = 0.08;
  static const double _addTileHoverBorderAlpha = 0.25;
  static const double _addTileIdleBorderAlpha = 0.1;
  static const double _addTileIconSize = 14;
  static const double _addTileFontSize = 11.5;
  static const double _addTileLetterSpacing = 0.15;

  @override
  State<AddCustomProfileTile> createState() => _AddCustomProfileTileState();
}

class _AddCustomProfileTileState extends State<AddCustomProfileTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: _isHovered
                ? Colors.white.withValues(
                    alpha: AddCustomProfileTile._tileHoverBgAlpha,
                  )
                : Colors.transparent,
            borderRadius: const BorderRadius.all(Radius.circular(7)),
            border: Border.all(
              color: Colors.white.withValues(
                alpha: _isHovered
                    ? AddCustomProfileTile._addTileHoverBorderAlpha
                    : AddCustomProfileTile._addTileIdleBorderAlpha,
              ),
              style: BorderStyle.solid,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.add_rounded,
                size: AddCustomProfileTile._addTileIconSize,
                color: _isHovered ? Colors.white : Colors.white70,
              ),
              const SizedBox(width: 6),
              Text(
                'Custom Profile',
                style: TextStyle(
                  color: _isHovered ? Colors.white : Colors.white70,
                  fontSize: AddCustomProfileTile._addTileFontSize,
                  fontWeight: FontWeight.w500,
                  letterSpacing: AddCustomProfileTile._addTileLetterSpacing,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
