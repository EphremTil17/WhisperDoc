import 'package:flutter/material.dart';
import 'package:flutter_client/services/transcription/groq_transcription_service.dart';
import 'package:provider/provider.dart';

class ProfileHubGroq extends StatelessWidget {
  const ProfileHubGroq({
    required this.isHovered,
    required this.onHoverChanged,
    required this.onOpen,
    super.key,
  });

  static const overlayAlpha = 0.7;
  static const _hoveredBackgroundAlpha = 0.1;
  static const _idleBackgroundAlpha = 0.03;
  static const _hoveredBorderAlpha = 0.2;
  static const _idleBorderAlpha = 0.1;
  static const _activeBadgeAlpha = 0.1;
  static const _inactiveBadgeAlpha = 0.1;
  static const _menuColorAlpha = 0.7;
  static const _tooltipVerticalOffset = 25.0;
  static const _hoverAnimationDuration = Duration(milliseconds: 200);
  static const _containerPadding = EdgeInsets.all(4);
  static const _hubRadius = BorderRadius.all(Radius.circular(20));
  static const _avatarRadius = 14.0;
  static const _avatarIconSize = 16.0;
  static const _menuIconSize = 20.0;
  static const _labelGap = SizedBox(width: 8);
  static const _trailingGap = SizedBox(width: 4);

  final bool isHovered;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onOpen;

  void _handleTap() {
    onOpen();
  }

  @override
  Widget build(BuildContext context) {
    final groqService = context.watch<GroqTranscriptionService>();
    final hasKey = groqService.hasValidCredentials;
    final backgroundColor = isHovered
        ? Colors.white.withValues(alpha: _hoveredBackgroundAlpha)
        : Colors.white.withValues(alpha: _idleBackgroundAlpha);
    final borderColor = isHovered
        ? Colors.white.withValues(alpha: _hoveredBorderAlpha)
        : Colors.white.withValues(alpha: _idleBorderAlpha);
    final badgeBackgroundColor = hasKey
        ? Colors.greenAccent.withValues(alpha: _activeBadgeAlpha)
        : Colors.orangeAccent.withValues(alpha: _inactiveBadgeAlpha);
    final badgeIcon = hasKey ? Icons.cloud_done : Icons.cloud_off;
    final badgeIconColor = hasKey ? Colors.greenAccent : Colors.orangeAccent;
    final menuColor = isHovered
        ? Colors.white
        : Colors.white.withValues(alpha: _menuColorAlpha);

    return Tooltip(
      message: hasKey ? 'Groq Cloud Profile' : 'Configure Groq Cloud',
      verticalOffset: _tooltipVerticalOffset,
      child: MouseRegion(
        onEnter: (_) => onHoverChanged(true),
        onExit: (_) => onHoverChanged(false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _handleTap,
          child: AnimatedContainer(
            duration: _hoverAnimationDuration,
            padding: _containerPadding,
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: _hubRadius,
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: _avatarRadius,
                  backgroundColor: badgeBackgroundColor,
                  child: Icon(
                    badgeIcon,
                    size: _avatarIconSize,
                    color: badgeIconColor,
                  ),
                ),
                _labelGap,
                Icon(Icons.menu, size: _menuIconSize, color: menuColor),
                _trailingGap,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
