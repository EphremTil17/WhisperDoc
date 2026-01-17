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
  final Stream<int> countdownStream;
  final VoidCallback onReconnect;
  final VoidCallback? onDismiss;

  const BanCountdownOverlay({
    super.key,
    required this.countdownStream,
    required this.onReconnect,
    this.onDismiss,
  });

  @override
  State<BanCountdownOverlay> createState() => _BanCountdownOverlayState();
}

class _BanCountdownOverlayState extends State<BanCountdownOverlay> {
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
        if (seconds == 0 && widget.onDismiss != null) {
          widget.onDismiss!();
        }
      }
    });
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0s';

    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;

    if (minutes > 0) {
      return '${minutes}m ${remainingSeconds}s';
    }
    return '${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final isBanned = _remainingSeconds > 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.red.withValues(alpha: 0.9),
            Colors.deepOrange.withValues(alpha: 0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.block, color: Colors.white, size: 48),
          const SizedBox(height: 16),
          const Text(
            'Connection Banned',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            isBanned
                ? 'Too many failed authentication attempts.\nRetry available in ${_formatDuration(_remainingSeconds)}'
                : 'Ban expired. You may reconnect now.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: isBanned ? null : widget.onReconnect,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: isBanned ? Colors.grey : Colors.deepOrange,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: Icon(isBanned ? Icons.timer : Icons.refresh),
            label: Text(
              isBanned ? 'Please Wait...' : 'Reconnect',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
