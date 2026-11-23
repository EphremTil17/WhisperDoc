import 'dart:async';

import 'package:flutter/foundation.dart';

import '../utility/logging_service.dart';

/// Retries a lost or unreachable connection with capped exponential backoff:
/// 2s, 4s, 8s … up to once a minute, until a connection succeeds ([reset]).
class ReconnectionManager {
  static const Duration _firstDelay = Duration(seconds: 2);
  static const Duration _maxDelay = Duration(minutes: 1);

  final LoggingService _logger = LoggingService();
  Timer? _timer;
  int _attempts = 0;

  int get attempts => _attempts;

  @visibleForTesting
  bool get isScheduled => _timer?.isActive ?? false;

  /// The wait before the next attempt, doubling per failed attempt.
  @visibleForTesting
  Duration get nextDelay {
    var delay = _firstDelay;
    for (var i = 0; i < _attempts && delay < _maxDelay; i++) {
      delay += delay;
    }

    return delay > _maxDelay ? _maxDelay : delay;
  }

  /// Schedules the next attempt unless one is already pending, the client is
  /// banned, or the last error was a credential the server refused.
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

    final delay = nextDelay;
    _logger.info(
      'Reconnect scheduled in ${delay.inSeconds}s (Attempt ${_attempts + 1})',
    );

    _timer = Timer(delay, () {
      _attempts++;
      unawaited(onRetry());
    });
  }

  /// Cancels any pending attempt and starts the backoff over.
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
