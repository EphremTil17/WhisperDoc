import 'dart:async';
import 'package:flutter/material.dart';

class RefinedIconButton extends StatefulWidget {
  const RefinedIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.iconColor,
    this.iconSize = _defaultIconSize,
    this.isPulsing = false,
    this.pulseColor,
  });

  static const double _defaultIconSize = 24;

  final IconData icon;
  final VoidCallback? onTap;
  final Color? iconColor;
  final double iconSize;
  final bool isPulsing;
  final Color? pulseColor;

  @override
  State<RefinedIconButton> createState() => _RefinedIconButtonState();
}

class _RefinedIconButtonState extends State<RefinedIconButton>
    with SingleTickerProviderStateMixin {
  static const double _hoverBackgroundAlpha = 0.2;
  static const double _pulsingBackgroundAlphaScale = 0.05;
  static const double _pulsingBackgroundAlphaBase = 0.08;
  static const double _hoverBorderAlpha = 0.5;
  static const double _pulsingBorderAlphaScale = 0.35;
  static const double _pulsingBorderAlphaBase = 0.15;
  static const double _idleBorderAlpha = 0.15;
  static const double _pulsingBorderWidthScale = 0.5;
  static const double _pulsingBorderWidthBase = 1;
  static const double _shadowAlphaScale = 0.1;
  static const double _shadowBlurScale = 8;
  static const double _shadowSpreadScale = 1;
  static const double _idlePulseValue = 0;

  bool _isHovering = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    if (widget.isPulsing) {
      unawaited(_pulseController.repeat(reverse: true));
    }
  }

  @override
  void didUpdateWidget(RefinedIconButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPulsing != oldWidget.isPulsing) {
      if (widget.isPulsing) {
        unawaited(_pulseController.repeat(reverse: true));
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            final pulseVal = widget.isPulsing
                ? Curves.easeInOut.transform(_pulseController.value)
                : _idlePulseValue;
            final glowColor = widget.pulseColor ?? Colors.white;
            final Color borderColor;

            if (_isHovering) {
              borderColor = Colors.white.withValues(alpha: _hoverBorderAlpha);
            } else if (widget.isPulsing) {
              borderColor = glowColor.withValues(
                alpha:
                    (pulseVal * _pulsingBorderAlphaScale) +
                    _pulsingBorderAlphaBase,
              );
            } else {
              borderColor = Colors.white.withValues(alpha: _idleBorderAlpha);
            }

            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _isHovering
                    ? Colors.white.withValues(alpha: _hoverBackgroundAlpha)
                    : glowColor.withValues(
                        alpha:
                            (pulseVal * _pulsingBackgroundAlphaScale) +
                            _pulsingBackgroundAlphaBase,
                      ),
                borderRadius: const BorderRadius.all(Radius.circular(8)),
                border: Border.all(
                  color: borderColor,
                  width: widget.isPulsing
                      ? (pulseVal * _pulsingBorderWidthScale) +
                            _pulsingBorderWidthBase
                      : _pulsingBorderWidthBase,
                ),
                boxShadow: widget.isPulsing
                    ? [
                        BoxShadow(
                          color: glowColor.withValues(
                            alpha: pulseVal * _shadowAlphaScale,
                          ),
                          blurRadius: pulseVal * _shadowBlurScale,
                          spreadRadius: pulseVal * _shadowSpreadScale,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                widget.icon,
                color: _isHovering
                    ? Colors.white
                    : (widget.iconColor ?? Colors.white70),
                size: widget.iconSize,
              ),
            );
          },
        ),
      ),
    );
  }
}
