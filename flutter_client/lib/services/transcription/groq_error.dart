import 'dart:convert';

/// Typed error for Groq Cloud transcription failures.
///
/// Maps HTTP status codes and JSON error bodies to user-friendly messages
/// that flow through [RecordingController.onError].
class GroqError implements Exception {
  final GroqErrorType type;
  final String message;
  final Duration? retryAfter;

  static const int _statusBadRequest = 400;
  static const int _statusUnauthorized = 401;
  static const int _statusTooLarge = 413;
  static const int _statusRateLimited = 429;
  static const int _statusServerError = 500;

  /// Human-readable message suitable for the UI error stream.
  String get userMessage {
    switch (type) {
      case GroqErrorType.invalidApiKey:
        return 'Invalid Groq API key. Check Settings.';
      case GroqErrorType.rateLimited:
        final delay = retryAfter;
        if (delay != null) {
          return 'Groq rate limit reached. Try again in ${delay.inSeconds} seconds.';
        }

        return 'Groq rate limit reached. Please wait and try again.';
      case GroqErrorType.fileTooLarge:
        return 'Audio file exceeds Groq free-tier limit. Record a shorter clip.';
      case GroqErrorType.serverError:
        return 'Groq service temporarily unavailable.';
      case GroqErrorType.networkError:
        return 'Cannot reach Groq Cloud. Check your connection.';
      case GroqErrorType.badRequest:
        return 'Groq request failed: $message';
      case GroqErrorType.unknown:
        return 'Groq error: $message';
    }
  }

  const GroqError({required this.type, required this.message, this.retryAfter});

  /// Parses an HTTP response into a typed [GroqError].
  factory GroqError.fromResponse(int statusCode, String body) {
    final String detail = _extractMessage(body);

    switch (statusCode) {
      case _statusBadRequest:
        return GroqError(type: GroqErrorType.badRequest, message: detail);
      case _statusUnauthorized:
        return GroqError(type: GroqErrorType.invalidApiKey, message: detail);
      case _statusTooLarge:
        return GroqError(type: GroqErrorType.fileTooLarge, message: detail);
      case _statusRateLimited:
        return GroqError(type: GroqErrorType.rateLimited, message: detail);
      default:
        if (statusCode >= _statusServerError) {
          return GroqError(type: GroqErrorType.serverError, message: detail);
        }

        return GroqError(type: GroqErrorType.unknown, message: detail);
    }
  }

  /// Creates a network-level error (DNS, timeout, socket).
  factory GroqError.network(String reason) =>
      GroqError(type: GroqErrorType.networkError, message: reason);

  @override
  String toString() => 'GroqError($type): $message';

  static String _extractMessage(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final error = json['error'] as Map<String, dynamic>?;

      return error?['message'] as String? ?? body;
    } catch (_) {
      return body.isNotEmpty ? body : 'Unknown error';
    }
  }
}

/// Categories of Groq API failures.
enum GroqErrorType {
  badRequest,
  invalidApiKey,
  fileTooLarge,
  rateLimited,
  serverError,
  networkError,
  unknown,
}
