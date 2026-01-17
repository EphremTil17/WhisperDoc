import 'dart:async';
import 'package:flutter_client/core/services/logging_service.dart';

/// Ban state tracking service for handling backend 1008 close codes.
///
/// Implements Active Defense awareness by:
/// - Parsing 1008 WebSocket close codes from backend
/// - Extracting ban duration from close reason strings
/// - Providing countdown timer for UI display
/// - Disabling auto-reconnect during ban period
///
/// Close Reason Format (from backend):
/// - "IP Banned. Cooldown: 300s"
/// - "Banned for 60s"
/// - "Retry in 240s"
class BanStateService {
  final LoggingService _logger = LoggingService();

  bool _isBanned = false;
  int _cooldownSeconds = 0;
  DateTime? _banExpiresAt;

  Timer? _countdownTimer;
  final StreamController<int> _cooldownController =
      StreamController<int>.broadcast();

  bool get isBanned => _isBanned;
  int get cooldownRemaining => _cooldownSeconds;
  Stream<int> get cooldownStream => _cooldownController.stream;

  /// Parse a WebSocket 1008 close reason and extract ban duration
  void parseBanMessage(String? closeReason) {
    if (closeReason == null || closeReason.isEmpty) {
      _logger.warning('Received 1008 close code without reason message');
      _setBan(
        300,
      ); // Default 5min ban from backend config (BAN_DURATION_SECONDS)
      return;
    }

    _logger.warning('Received ban message: $closeReason');

    // Extract duration using regex patterns
    // Patterns: "Cooldown: 300s", "Banned for 60s", "Retry in 240s"
    final patterns = [
      RegExp(r'Cooldown:\s*(\d+)s?', caseSensitive: false),
      RegExp(r'Banned for\s*(\d+)s?', caseSensitive: false),
      RegExp(r'Retry in\s*(\d+)s?', caseSensitive: false),
      RegExp(
        r'(\d+)s',
        caseSensitive: false,
      ), // Fallback: any number followed by 's'
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(closeReason);
      if (match != null && match.groupCount >= 1) {
        final duration = int.tryParse(match.group(1)!);
        if (duration != null) {
          _setBan(duration);
          return;
        }
      }
    }

    // If no pattern matched, use default
    _logger.warning(
      'Could not parse ban duration from: $closeReason, using default',
    );
    _setBan(300);
  }

  /// Manually clear the ban (for testing or after manual user action)
  void clearBan() {
    if (!_isBanned) return;

    _logger.info('Ban cleared manually');
    _isBanned = false;
    _cooldownSeconds = 0;
    _banExpiresAt = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _cooldownController.add(0);
  }

  /// Dispose resources
  void dispose() {
    _countdownTimer?.cancel();
    unawaited(_cooldownController.close());
  }

  // --- Private Methods ---

  void _setBan(int durationSeconds) {
    _isBanned = true;
    _cooldownSeconds = durationSeconds;
    _banExpiresAt = DateTime.now().add(Duration(seconds: durationSeconds));

    _logger.warning('IP banned for $durationSeconds seconds');

    // Cancel existing timer
    _countdownTimer?.cancel();

    // Start countdown timer (updates every second)
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();

      if (_banExpiresAt != null && now.isBefore(_banExpiresAt!)) {
        _cooldownSeconds = _banExpiresAt!.difference(now).inSeconds;
        _cooldownController.add(_cooldownSeconds);
      } else {
        // Ban expired
        _logger.info('Ban cooldown expired, reconnection allowed');
        _isBanned = false;
        _cooldownSeconds = 0;
        _banExpiresAt = null;
        _cooldownController.add(0);
        timer.cancel();
        _countdownTimer = null;
      }
    });

    // Emit initial countdown value
    _cooldownController.add(0);
    _cooldownController.add(_cooldownSeconds);
  }
}
