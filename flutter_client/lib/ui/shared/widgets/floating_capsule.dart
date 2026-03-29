import 'package:flutter/material.dart';

class FloatingCapsule extends StatefulWidget {
  const FloatingCapsule({
    super.key,
    required this.isRecording,
    required this.onTap,
    this.enabled = true,
  });

  final bool isRecording;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<FloatingCapsule> createState() => _FloatingCapsuleState();
}

class _FloatingCapsuleState extends State<FloatingCapsule> {
  static const double _enabledOpacity = 1.0;
  static const double _disabledOpacity = 0.4;
  static const double _recordingHoverBackgroundAlpha = 0.9;
  static const double _recordingBackgroundAlpha = 1.0;
  static const double _idleHoverBackgroundAlpha = 0.2;
  static const double _idleBackgroundAlpha = 0.1;
  static const double _hoverShadowAlpha = 0.4;
  static const double _shadowAlpha = 0.3;
  static const double _hoverBlurRadius = 25.0;
  static const double _blurRadius = 20.0;
  static const double _iconSize = 20.0;
  static const double _fontSize = 14.0;

  bool _isHovering = false;

  double _resolveBackgroundAlpha() {
    if (widget.isRecording) {
      return _isHovering
          ? _recordingHoverBackgroundAlpha
          : _recordingBackgroundAlpha;
    }

    return _isHovering ? _idleHoverBackgroundAlpha : _idleBackgroundAlpha;
  }

  @override
  Widget build(BuildContext context) {
    // Determine status color/text based on state
    final (Color color, String text) = switch ((
      widget.isRecording,
      widget.enabled,
    )) {
      (true, _) => (const Color(0xFFDC143C), 'Stop Recording'),
      (false, true) => (Colors.white24, 'Ready'),
      (false, false) => (Colors.white10, 'Offline'),
    };

    final opacity = widget.enabled ? _enabledOpacity : _disabledOpacity;
    final backgroundAlpha = _resolveBackgroundAlpha();
    Color borderColor;
    if (widget.isRecording) {
      borderColor = Colors.redAccent;
    } else if (widget.enabled) {
      borderColor = _isHovering ? Colors.white54 : Colors.white24;
    } else {
      borderColor = Colors.white10;
    }

    return MouseRegion(
      onEnter: widget.enabled
          ? (_) => setState(() => _isHovering = true)
          : null,
      onExit: widget.enabled
          ? (_) => setState(() => _isHovering = false)
          : null,
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: backgroundAlpha),
            borderRadius: const BorderRadius.all(Radius.circular(30)),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              if (widget.enabled)
                BoxShadow(
                  color:
                      (widget.isRecording
                              ? const Color(0xFFDC143C)
                              : Colors.black)
                          .withValues(
                            alpha: _isHovering
                                ? _hoverShadowAlpha
                                : _shadowAlpha,
                          ),
                  blurRadius: _isHovering ? _hoverBlurRadius : _blurRadius,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Opacity(
            opacity: opacity,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.isRecording ? Icons.stop : Icons.mic,
                  color: widget.enabled ? Colors.white : Colors.white38,
                  size: _iconSize,
                ),
                const SizedBox(width: 12),
                Text(
                  text,
                  style: TextStyle(
                    color: widget.enabled ? Colors.white : Colors.white38,
                    fontWeight: FontWeight.w600,
                    fontSize: _fontSize,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
