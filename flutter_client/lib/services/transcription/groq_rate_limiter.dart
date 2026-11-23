import 'package:flutter_client/infrastructure/constants/app_constants.dart';

/// Client-side rate-limit tracker for the Groq free tier.
///
/// A sliding-window requests-per-minute counter and a daily counter keep the
/// user from sending requests that would certainly be refused, and a
/// server-mandated cool-down (`retry-after` on a 429) is honoured through
/// [backOff].
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

  /// Refuses requests for [cooldown], as the server asked.
  void backOff(Duration cooldown) {
    _retryAfterUntil = DateTime.now().toUtc().add(cooldown);
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
