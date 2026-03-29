import 'package:flutter/material.dart';
import 'package:flutter_client/controllers/profile_controller.dart';
import 'package:flutter_client/ui/shared/widgets/profile_hub_avatar.dart';
import 'package:provider/provider.dart';

class ProfileHubBackend extends StatelessWidget {
  const ProfileHubBackend({
    required this.isHovered,
    required this.pulseAnimation,
    required this.onHoverChanged,
    required this.onOpen,
    super.key,
  });

  static const _hoveredBackgroundAlpha = 0.1;
  static const _hoveredBorderAlpha = 0.2;
  static const _idleBorderAlpha = 0.1;
  static const _idleShadowAlpha = 0.2;
  static const _idleIconAlpha = 0.7;
  static const _baseGlowAlpha = 0.05;
  static const _pulseGlowAlphaFactor = 0.05;
  static const _pulseBorderAlphaBase = 0.15;
  static const _pulseBorderAlphaFactor = 0.35;
  static const _pulseBorderWidthBase = 1.0;
  static const _pulseBorderWidthFactor = 0.5;
  static const _pulseShadowAlphaFactor = 0.2;
  static const _shadowBlurRadius = 10.0;
  static const _pulseBlurRadiusFactor = 10.0;
  static const _pulseSpreadRadiusFactor = 2.0;
  static const _tooltipVerticalOffset = 25.0;
  static const _hoverAnimationDuration = Duration(milliseconds: 200);
  static const _containerPadding = EdgeInsets.all(4);
  static const _hubRadius = BorderRadius.all(Radius.circular(20));
  static const _idleShadowOffset = Offset(0, 4);
  static const _menuIconSize = 20.0;
  static const _labelGap = SizedBox(width: 8);
  static const _trailingGap = SizedBox(width: 4);

  final bool isHovered;
  final Animation<double> pulseAnimation;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback onOpen;

  void _handleTap() {
    onOpen();
  }

  Color _buildBackgroundColor({
    required Color glowColor,
    required bool isPulsing,
    required double pulseValue,
  }) {
    if (isHovered) {
      return Colors.white.withValues(alpha: _hoveredBackgroundAlpha);
    }

    if (isPulsing) {
      final pulseAlpha = (pulseValue * _pulseGlowAlphaFactor) + _baseGlowAlpha;

      return glowColor.withValues(alpha: pulseAlpha);
    }

    return glowColor.withValues(alpha: _baseGlowAlpha);
  }

  Color _buildBorderColor({
    required Color glowColor,
    required bool isPulsing,
    required double pulseValue,
  }) {
    if (isHovered) {
      return Colors.white.withValues(alpha: _hoveredBorderAlpha);
    }

    if (isPulsing) {
      final borderAlpha =
          (pulseValue * _pulseBorderAlphaFactor) + _pulseBorderAlphaBase;

      return glowColor.withValues(alpha: borderAlpha);
    }

    return Colors.white.withValues(alpha: _idleBorderAlpha);
  }

  List<BoxShadow>? _buildShadow({
    required Color glowColor,
    required bool isPulsing,
    required double pulseValue,
  }) {
    if (!isHovered && !isPulsing) {
      return null;
    }

    final color = isPulsing
        ? glowColor.withValues(alpha: pulseValue * _pulseShadowAlphaFactor)
        : Colors.black.withValues(alpha: _idleShadowAlpha);
    final blurRadius = isPulsing
        ? pulseValue * _pulseBlurRadiusFactor
        : _shadowBlurRadius;
    final offset = isPulsing ? Offset.zero : _idleShadowOffset;
    final spreadRadius = isPulsing
        ? pulseValue * _pulseSpreadRadiusFactor
        : 0.0;

    return [
      BoxShadow(
        color: color,
        blurRadius: blurRadius,
        offset: offset,
        spreadRadius: spreadRadius,
      ),
    ];
  }

  Color _buildMenuColor({required Color glowColor, required bool isPulsing}) {
    if (isHovered) {
      return Colors.white;
    }

    if (isPulsing) {
      return glowColor;
    }

    return Colors.white.withValues(alpha: _idleIconAlpha);
  }

  @override
  Widget build(BuildContext context) {
    final profileController = context.watch<ProfileController>();
    final user = profileController.currentUser;
    final updateUi = profileController.updateUI;
    final glowColor = updateUi.glowColor;

    return Tooltip(
      message: 'Manage Profile',
      verticalOffset: _tooltipVerticalOffset,
      child: MouseRegion(
        onEnter: (_) => onHoverChanged(true),
        onExit: (_) => onHoverChanged(false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _handleTap,
          child: AnimatedBuilder(
            animation: pulseAnimation,
            builder: (context, child) {
              final pulseValue = updateUi.isPulsing
                  ? pulseAnimation.value
                  : 0.0;
              final backgroundColor = _buildBackgroundColor(
                glowColor: glowColor,
                isPulsing: updateUi.isPulsing,
                pulseValue: pulseValue,
              );
              final borderColor = _buildBorderColor(
                glowColor: glowColor,
                isPulsing: updateUi.isPulsing,
                pulseValue: pulseValue,
              );
              final borderWidth = updateUi.isPulsing
                  ? (pulseValue * _pulseBorderWidthFactor) +
                        _pulseBorderWidthBase
                  : _pulseBorderWidthBase;
              final shadow = _buildShadow(
                glowColor: glowColor,
                isPulsing: updateUi.isPulsing,
                pulseValue: pulseValue,
              );
              final menuColor = _buildMenuColor(
                glowColor: glowColor,
                isPulsing: updateUi.isPulsing,
              );

              return AnimatedContainer(
                duration: _hoverAnimationDuration,
                padding: _containerPadding,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: _hubRadius,
                  border: Border.all(color: borderColor, width: borderWidth),
                  boxShadow: shadow,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ProfileHubAvatar(user: user),
                    _labelGap,
                    Icon(Icons.menu, size: _menuIconSize, color: menuColor),
                    _trailingGap,
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
