import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/services/transcription/groq_error.dart';

void main() {
  group('GroqError', () {
    const int badRequestStatus = 400;
    const int unauthorizedStatus = 401;
    const int contentTooLargeStatus = 413;
    const int teapotStatus = 418;
    const int rateLimitedStatus = 429;
    const int serverErrorStatus = 500;
    const int serviceUnavailableStatus = 503;

    test('userMessage produces expected messages for all error types', () {
      expect(
        const GroqError(
          type: GroqErrorType.invalidApiKey,
          message: 'Invalid key',
        ).userMessage,
        'Invalid Groq API key. Check Settings.',
      );

      expect(
        const GroqError(
          type: GroqErrorType.rateLimited,
          message: 'Rate limit',
          retryAfter: Duration(seconds: 45),
        ).userMessage,
        'Groq rate limit reached. Try again in 45 seconds.',
      );

      expect(
        const GroqError(
          type: GroqErrorType.rateLimited,
          message: 'Rate limit',
        ).userMessage,
        'Groq rate limit reached. Please wait and try again.',
      );

      expect(
        const GroqError(
          type: GroqErrorType.fileTooLarge,
          message: 'Too big',
        ).userMessage,
        'Audio file exceeds Groq free-tier limit. Record a shorter clip.',
      );

      expect(
        const GroqError(
          type: GroqErrorType.serverError,
          message: 'Service down',
        ).userMessage,
        'Groq service temporarily unavailable.',
      );

      expect(
        const GroqError(
          type: GroqErrorType.networkError,
          message: 'DNS failure',
        ).userMessage,
        'Cannot reach Groq Cloud. Check your connection.',
      );

      expect(
        const GroqError(
          type: GroqErrorType.badRequest,
          message: 'Bad audio format',
        ).userMessage,
        'Groq request failed: Bad audio format',
      );

      expect(
        const GroqError(
          type: GroqErrorType.unknown,
          message: 'Mysterious glitch',
        ).userMessage,
        'Groq error: Mysterious glitch',
      );
    });

    test('fromResponse handles structured JSON error bodies', () {
      final err400 = GroqError.fromResponse(
        badRequestStatus,
        '{"error": {"message": "Invalid language param"}}',
      );
      expect(err400.type, GroqErrorType.badRequest);
      expect(err400.message, 'Invalid language param');

      final err401 = GroqError.fromResponse(
        unauthorizedStatus,
        '{"error": {"message": "Invalid API Key"}}',
      );
      expect(err401.type, GroqErrorType.invalidApiKey);

      final err413 = GroqError.fromResponse(
        contentTooLargeStatus,
        '{"error": "Too big"}',
      );
      expect(err413.type, GroqErrorType.fileTooLarge);

      final err429 = GroqError.fromResponse(rateLimitedStatus, 'Rate limited');
      expect(err429.type, GroqErrorType.rateLimited);

      final err503 = GroqError.fromResponse(
        serviceUnavailableStatus,
        'Service unavailable',
      );
      expect(err503.type, GroqErrorType.serverError);

      final err418 = GroqError.fromResponse(teapotStatus, "I'm a teapot");
      expect(err418.type, GroqErrorType.unknown);
    });

    test('fromResponse handles empty and non-JSON bodies', () {
      final emptyErr = GroqError.fromResponse(serverErrorStatus, '');
      expect(emptyErr.message, 'Unknown error');

      final plainErr = GroqError.fromResponse(
        badRequestStatus,
        'Plain text failure',
      );
      expect(plainErr.message, 'Plain text failure');
    });

    test('network constructor creates networkError', () {
      final netErr = GroqError.network('Socket exception');
      expect(netErr.type, GroqErrorType.networkError);
      expect(netErr.message, 'Socket exception');
      expect(
        netErr.toString(),
        contains('GroqError(GroqErrorType.networkError)'),
      );
    });
  });
}
