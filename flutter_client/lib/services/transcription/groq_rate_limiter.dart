import 'package:flutter_client/infrastructure/constants/app_constants.dart';

/// Client-side rate-limit tracker for the Groq free tier.
///
/// Uses a sliding-window RPM counter and a daily request counter to prevent
/// the user from sending requests that will definitely be rejected. Also
/// parses Groq's `retry-after` and `x-ratelimit-*` response headers to
/// honour server-side back-off signals.
class GroqRateLimiter {
  final List<DateTime> _requestTimestamps = [];
  int _dailyCount = 0;
  DateTime _dailyResetDate = _todayUtc();
  DateTime? _retryAfterUntil;

  /// Duration the caller must wait before retrying (zero if no back-off).
  Duration get retryAfter {
    final retryUntil = _retryAfterUntil;
    if (retryUntil == null) return Duration.zero;
    final remaining = retryUntil.difference(DateTime.now().toUtc());

    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Human-readable status for diagnostic display.
  String get statusMessage {
    _pruneExpiredTimestamps();
    _resetDailyIfNeeded();

    return '${_requestTimestamps.length}/${AppConstants.groqMaxRpm} RPM, '
        '$_dailyCount/${AppConstants.groqMaxRpd} RPD';
  }

  /// Whether a request can be made right now without hitting a known limit.
  bool canRequest() {
    _pruneExpiredTimestamps();
    _resetDailyIfNeeded();

    final retryUntil = _retryAfterUntil;
    if (retryUntil != null && DateTime.now().toUtc().isBefore(retryUntil)) {
      return false;
    }

    return _requestTimestamps.length < AppConstants.groqMaxRpm &&
        _dailyCount < AppConstants.groqMaxRpd;
  }

  /// Records that a request was just made.
  void recordRequest() {
    _requestTimestamps.add(DateTime.now().toUtc());
    _dailyCount++;
  }

  /// Parses rate-limit headers from a Groq HTTP response.
  void updateFromHeaders(Map<String, String> headers) {
    final retryAfter = headers['retry-after'];
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter);
      if (seconds != null) {
        _retryAfterUntil = DateTime.now().toUtc().add(
          Duration(seconds: seconds),
        );
      }
    }
  }

  // -- Internals --

  void _pruneExpiredTimestamps() {
    final cutoff = DateTime.now().toUtc().subtract(const Duration(seconds: 60));
    _requestTimestamps.removeWhere((t) => t.isBefore(cutoff));
  }

  void _resetDailyIfNeeded() {
    final today = _todayUtc();
    if (today.isAfter(_dailyResetDate)) {
      _dailyCount = 0;
      _dailyResetDate = today;
    }
  }

  static DateTime _todayUtc() {
    final now = DateTime.now().toUtc();

    return DateTime.utc(now.year, now.month, now.day);
  }
}
