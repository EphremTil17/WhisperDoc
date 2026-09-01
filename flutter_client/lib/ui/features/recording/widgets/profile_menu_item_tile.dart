import 'package:flutter/material.dart';
import 'package:flutter_client/logic/mappers/dictation_profile_ui_mapper.dart';
import 'package:flutter_client/logic/models/dictation_profile_spec.dart';

/// An individual profile selection tile within the [ProfileActionButton] dropdown.
class ProfileMenuItemTile extends StatefulWidget {
  const ProfileMenuItemTile({
    required this.profile,
    required this.isSelected,
    required this.isEnabled,
    required this.isKeyBlocked,
    required this.onTap,
    this.onEdit,
    super.key,
  });

  final DictationProfileSpec profile;
  final bool isSelected;
  final bool isEnabled;
  final bool isKeyBlocked;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;

  static const double _tileSelectedBgAlpha = 0.15;
  static const double _tileHoverBgAlpha = 0.08;
  static const double _tileSelectedBorderAlpha = 0.28;
  static const double _tileIconSize = 15;
  static const double _tileTitleFontSize = 12.5;
  static const double _tileTitleLetterSpacing = 0.15;
  static const double _tileTitleLineHeight = 1.25;
  static const double _tileSubtitleFontSize = 10.5;
  static const double _tileSubtitleLetterSpacing = 0.05;
  static const double _tileSubtitleLineHeight = 1.2;
  static const double _tileEditIconSize = 14;
  static const double _tileEditIconAlpha = 0.65;
  static const double _tileBlockedIconSize = 13;

  @override
  State<ProfileMenuItemTile> createState() => _ProfileMenuItemTileState();
}

class _ProfileMenuItemTileState extends State<ProfileMenuItemTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    Color tileBg;
    if (widget.isSelected) {
      tileBg = Colors.white.withValues(
        alpha: ProfileMenuItemTile._tileSelectedBgAlpha,
      );
    } else if (_isHovered && widget.isEnabled) {
      tileBg = Colors.white.withValues(
        alpha: ProfileMenuItemTile._tileHoverBgAlpha,
      );
    } else {
      tileBg = Colors.transparent;
    }

    final Color titleColor;
    final Color subtitleColor;
    final Color iconColor;
    if (!widget.isEnabled) {
      titleColor = const Color(0xFF606068);
      subtitleColor = const Color(0xFF606068);
      iconColor = const Color(0xFF606068);
    } else if (widget.isSelected) {
      titleColor = Colors.white;
      subtitleColor = const Color(0xFFD0D0D8);
      iconColor = Colors.white;
    } else {
      titleColor = const Color(0xFFE8E8EE);
      subtitleColor = const Color(0xFFB0B0B8);
      iconColor = const Color(0xFFCCCCCC);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: widget.isEnabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: tileBg,
            borderRadius: const BorderRadius.all(Radius.circular(7)),
            border: Border.all(
              color: widget.isSelected
                  ? Colors.white.withValues(
                      alpha: ProfileMenuItemTile._tileSelectedBorderAlpha,
                    )
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                DictationProfileUiMapper.iconFor(widget.profile),
                size: ProfileMenuItemTile._tileIconSize,
                color: iconColor,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.profile.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: titleColor,
                        fontSize: ProfileMenuItemTile._tileTitleFontSize,
                        fontWeight: widget.isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        letterSpacing:
                            ProfileMenuItemTile._tileTitleLetterSpacing,
                        height: ProfileMenuItemTile._tileTitleLineHeight,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DictationProfileUiMapper.subtitleFor(
                        widget.profile,
                        isKeyBlocked: widget.isKeyBlocked,
                      ),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: ProfileMenuItemTile._tileSubtitleFontSize,
                        fontWeight: FontWeight.normal,
                        letterSpacing:
                            ProfileMenuItemTile._tileSubtitleLetterSpacing,
                        height: ProfileMenuItemTile._tileSubtitleLineHeight,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onEdit != null)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onEdit,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6, right: 4),
                      child: Icon(
                        Icons.edit_outlined,
                        size: ProfileMenuItemTile._tileEditIconSize,
                        color: Colors.white.withValues(
                          alpha: ProfileMenuItemTile._tileEditIconAlpha,
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.isSelected)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.check_rounded,
                    size: ProfileMenuItemTile._tileIconSize,
                    color: Colors.white,
                  ),
                )
              else if (widget.isKeyBlocked)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.key_off_outlined,
                    size: ProfileMenuItemTile._tileBlockedIconSize,
                    color: Color(0xFF606068),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
