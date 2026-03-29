import 'dart:async';
import 'package:flutter/foundation.dart';
import '../utility/logging_service.dart';

/// Orchestrates WebSocket reconnection attempts with security "Kill Switch" enforcement.
class ReconnectionManager {
  final LoggingService _logger = LoggingService();
  Timer? _timer;
  int _attempts = 0;

  int get attempts => _attempts;

  @visibleForTesting
  bool get isScheduled => _timer?.isActive ?? false;

  /// Schedules a reconnection attempt if not blocked by security policy.
  void schedule({
    required Future<void> Function() onRetry,
    String? lastError,
    bool isBanned = false,
  }) {
    if (_timer?.isActive ?? false) return;
    if (isBanned) return;

    // KILL SWITCH: Prevent hammering on terminal authentication failures
    if (lastError != null) {
      final err = lastError.toLowerCase();
      if (err.contains('no oidc session') ||
          err.contains('authentication token') ||
          err.contains('access denied') ||
          err.contains('authentication failed') ||
          err.contains('invalid credentials')) {
        _logger.warning('Auto-reconnect aborted: Terminal Auth Failure ($err)');

        return;
      }
    }

    const delay = Duration(seconds: 5);
    _logger.info(
      'Reconnect scheduled in ${delay.inSeconds}s (Attempt ${_attempts + 1})',
    );

    _timer = Timer(delay, () {
      _attempts++;
      unawaited(onRetry());
    });
  }

  /// Resets the reconnection state.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _attempts = 0;
  }

  /// Cancels any active timer.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
