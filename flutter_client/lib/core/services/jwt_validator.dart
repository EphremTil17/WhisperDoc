import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter_client/core/services/logging_service.dart';

/// JWT token validator for expiry warnings and token type detection.
///
/// Provides utility methods for:
/// - Detecting if a credential is a JWT vs static API key
/// - Calculating time until JWT expiration
/// - Generating user-friendly expiry warnings
class JWTValidator {
  final LoggingService _logger = LoggingService();

  /// Check if a token string is a JWT (has 3 dot-separated segments)
  bool isJWT(String token) {
    return token.split('.').length == 3;
  }

  /// Get time remaining until JWT expires, or null if not a JWT/no exp claim
  Duration? getTimeUntilExpiry(String token) {
    if (!isJWT(token)) return null;

    try {
      final jwt = JWT.decode(token);
      final payload = jwt.payload as Map<String, dynamic>?;
      if (payload == null) return null;

      final exp = payload['exp'];
      if (exp == null) return null;

      // exp is in seconds since Unix epoch
      final expiryTime = DateTime.fromMillisecondsSinceEpoch(
        (exp as int) * 1000,
        isUtc: true,
      );
      final remaining = expiryTime.difference(DateTime.now().toUtc());

      return remaining;
    } catch (e) {
      _logger.warning('Failed to decode JWT for expiry check: $e');
      return null;
    }
  }

  /// Get user-friendly expiry warning message, or null if > 2 hours remaining
  String? getExpiryWarning(String token) {
    final timeLeft = getTimeUntilExpiry(token);
    if (timeLeft == null || timeLeft.inHours >= 2) {
      return null;
    }

    if (timeLeft.isNegative) {
      return 'Your access token has expired. Please reauthenticate.';
    }

    final hours = timeLeft.inHours;
    final minutes = timeLeft.inMinutes % 60;

    if (hours > 0) {
      return 'Your access token expires in $hours hour${hours > 1 ? 's' : ''} and $minutes minute${minutes > 1 ? 's' : ''}.';
    } else {
      return 'Your access token expires in $minutes minute${minutes > 1 ? 's' : ''}.';
    }
  }

  /// Get token type label for UI display
  String getTokenLabel(String token) {
    return isJWT(token) ? 'Access Token (JWT)' : 'API Key';
  }
}
