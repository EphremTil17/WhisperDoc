import 'dart:ui';
import 'package:flutter/material.dart';

class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.blur = _defaultBlur,
    this.opacity = _defaultOpacity,
    this.color,
    this.borderRadius,
    this.padding = const EdgeInsets.all(16.0),
    this.margin = EdgeInsets.zero,
    this.border = true,
  });

  static const _defaultBlur = 10.0;
  static const _defaultOpacity = 0.1;
  static const _borderAlpha = 0.1;

  final Widget child;
  final double blur;
  final double opacity;
  final Color? color;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final bool border;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius:
            borderRadius ?? const BorderRadius.all(Radius.circular(16)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: (color ?? Colors.white).withValues(alpha: opacity),
              borderRadius:
                  borderRadius ?? const BorderRadius.all(Radius.circular(16)),
              border: border
                  ? Border.all(
                      color: Colors.white.withValues(alpha: _borderAlpha),
                    )
                  : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
