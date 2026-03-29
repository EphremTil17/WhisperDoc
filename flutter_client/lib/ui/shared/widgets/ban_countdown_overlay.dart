import 'package:flutter/material.dart';
import 'dart:async';

/// Ban countdown overlay widget displayed when IP is banned by the backend.
///
/// Shows:
/// - Warning message about ban status
/// - Countdown timer showing remaining seconds
/// - Disabled reconnect button during cooldown
/// - Enabled reconnect button after cooldown expires
///
/// Designed to be shown as a modal overlay or integrated into status UI.
class BanCountdownOverlay extends StatefulWidget {
  const BanCountdownOverlay({
    super.key,
    required this.countdownStream,
    required this.onReconnect,
    this.onDismiss,
  });

  final Stream<int> countdownStream;
  final VoidCallback onReconnect;
  final VoidCallback? onDismiss;

  @override
  State<BanCountdownOverlay> createState() => _BanCountdownOverlayState();
}

class _BanCountdownOverlayState extends State<BanCountdownOverlay> {
  static const _containerPadding = 20.0;
  static const _gradientAlpha = 0.9;
  static const _borderRadius = 12.0;
  static const _shadowAlpha = 0.3;
  static const _shadowBlurRadius = 10.0;
  static const _shadowSpreadRadius = 2.0;
  static const _iconSize = 48.0;
  static const _iconGap = SizedBox(height: 16);
  static const _titleFontSize = 24.0;
  static const _titleGap = SizedBox(height: 12);
  static const _bodyFontSize = 16.0;
  static const _buttonGap = SizedBox(height: 24);
  static const _buttonHorizontalPadding = 32.0;
  static const _buttonVerticalPadding = 16.0;
  static const _buttonBorderRadius = 8.0;
  static const _buttonFontSize = 16.0;
  static const _secondsPerMinute = 60;

  int _remainingSeconds = 0;
  StreamSubscription<int>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.countdownStream.listen((seconds) {
      if (mounted) {
        setState(() {
          _remainingSeconds = seconds;
        });

        // Auto-dismiss when countdown reaches 0 if dismiss callback provided
        final onDismiss = widget.onDismiss;
        if (seconds == 0 && onDismiss != null) {
          onDismiss();
        }
      }
    });
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0s';

    final minutes = seconds ~/ _secondsPerMinute;
    final remainingSeconds = seconds % _secondsPerMinute;

    if (minutes > 0) {
      return '${minutes}m ${remainingSeconds}s';
    }

    return '${seconds}s';
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isBanned = _remainingSeconds > 0;

    return Container(
      padding: const EdgeInsets.all(_containerPadding),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.red.withValues(alpha: _gradientAlpha),
            Colors.deepOrange.withValues(alpha: _gradientAlpha),
          ],
        ),
        borderRadius: const BorderRadius.all(Radius.circular(_borderRadius)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _shadowAlpha),
            blurRadius: _shadowBlurRadius,
            spreadRadius: _shadowSpreadRadius,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.block, color: Colors.white, size: _iconSize),
          _iconGap,
          const Text(
            'Connection Banned',
            style: TextStyle(
              color: Colors.white,
              fontSize: _titleFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
          _titleGap,
          Text(
            isBanned
                ? 'Too many failed authentication attempts.\nRetry available in ${_formatDuration(_remainingSeconds)}'
                : 'Ban expired. You may reconnect now.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: _bodyFontSize,
            ),
          ),
          _buttonGap,
          ElevatedButton.icon(
            onPressed: isBanned ? null : widget.onReconnect,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: isBanned ? Colors.grey : Colors.deepOrange,
              padding: const EdgeInsets.symmetric(
                horizontal: _buttonHorizontalPadding,
                vertical: _buttonVerticalPadding,
              ),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(
                  Radius.circular(_buttonBorderRadius),
                ),
              ),
            ),
            icon: Icon(isBanned ? Icons.timer : Icons.refresh),
            label: Text(
              isBanned ? 'Please Wait...' : 'Reconnect',
              style: const TextStyle(
                fontSize: _buttonFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
