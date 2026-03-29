import 'dart:async';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import '../utility/logging_service.dart';

/// Manages the WebSocket idle timeout heartbeat.
class HeartbeatManager {
  final Duration timeout = AppConstants.wsIdleTimeout;

  final LoggingService _logger = LoggingService();
  Timer? _idleTimer;

  /// Resets the idle timer. Should be called on every inbound/outbound event.
  void reset({required void Function() onTimeout}) {
    _idleTimer?.cancel();
    _idleTimer = Timer(timeout, () {
      _logger.info('Idle timeout reached (${timeout.inMinutes}m)');
      onTimeout();
    });
  }

  /// Stops the heartbeat management.
  void stop() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }
}
