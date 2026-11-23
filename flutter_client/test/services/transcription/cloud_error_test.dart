// HTTP status codes are the subject under test, read best as written.
// ignore_for_file: no-magic-number
import 'package:flutter_client/services/transcription/cloud_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CloudError error(CloudErrorType type, {Duration? retryAfter}) => CloudError(
    service: 'OpenRouter',
    type: type,
    message: 'why',
    retryAfter: retryAfter,
  );

  group('CloudError.userMessage', () {
    test('a refusal and an empty clip say what happened', () {
      expect(
        error(CloudErrorType.refused).userMessage,
        'OpenRouter refused the request: why',
      );
      expect(
        error(CloudErrorType.noAudio).userMessage,
        'No audio was recorded. Please check your microphone.',
      );
    });

    test('names the service in every message', () {
      expect(
        error(CloudErrorType.invalidApiKey).userMessage,
        'Invalid OpenRouter API key. Check Account.',
      );
      expect(
        error(CloudErrorType.insufficientCredits).userMessage,
        'Your OpenRouter credits ran out. Add credits to keep dictating.',
      );
      expect(
        error(CloudErrorType.modelRetired).userMessage,
        'OpenRouter no longer serves this model. Choose another in Account.',
      );
      expect(
        error(CloudErrorType.modelUnavailable).userMessage,
        'This model isn’t available on OpenRouter right now. '
        'Choose another in Account.',
      );
      expect(
        error(CloudErrorType.fileTooLarge).userMessage,
        'This recording is too long for OpenRouter. Record a shorter clip.',
      );
      expect(
        error(CloudErrorType.serverError).userMessage,
        'OpenRouter is temporarily unavailable.',
      );
      expect(
        error(CloudErrorType.networkError).userMessage,
        'Cannot reach OpenRouter. Check your connection.',
      );
      expect(
        error(CloudErrorType.badRequest).userMessage,
        'OpenRouter request failed: why',
      );
      expect(
        error(CloudErrorType.unknown).userMessage,
        'OpenRouter error: why',
      );
    });

    test('a rate limit says how long to wait when the service said', () {
      expect(
        error(
          CloudErrorType.rateLimited,
          retryAfter: const Duration(seconds: 12),
        ).userMessage,
        'OpenRouter rate limit reached. Try again in 12 seconds.',
      );
      expect(
        error(CloudErrorType.rateLimited).userMessage,
        'OpenRouter rate limit reached. Please wait and try again.',
      );
    });

    test('toString carries the service, type and detail', () {
      expect(
        error(CloudErrorType.unknown).toString(),
        'CloudError(OpenRouter, CloudErrorType.unknown): why',
      );
    });
  });

  group('CloudError.fromResponse', () {
    CloudErrorType typeOf(int status, [String body = '{}']) =>
        CloudError.fromResponse('Groq', status, body).type;

    test('maps each status to the category the app acts on', () {
      expect(typeOf(400), CloudErrorType.badRequest);
      expect(typeOf(401), CloudErrorType.invalidApiKey);
      expect(typeOf(402), CloudErrorType.insufficientCredits);
      expect(typeOf(403), CloudErrorType.refused);
      expect(typeOf(404), CloudErrorType.modelUnavailable);
      expect(typeOf(413), CloudErrorType.fileTooLarge);
      expect(typeOf(429), CloudErrorType.rateLimited);
      expect(typeOf(500), CloudErrorType.serverError);
      expect(typeOf(503), CloudErrorType.serverError);
      expect(typeOf(418), CloudErrorType.unknown);
    });

    test('a 400 naming a model that does not exist means it was retired', () {
      final e = CloudError.fromResponse(
        'OpenRouter',
        400,
        '{"error":{"message":"Model acme/gone does not exist","code":400}}',
      );

      expect(e.type, CloudErrorType.modelRetired);
      expect(e.message, 'Model acme/gone does not exist');
      expect(e.service, 'OpenRouter');
    });

    test('so does an id OpenRouter calls invalid', () {
      final e = CloudError.fromResponse(
        'OpenRouter',
        400,
        '{"error":{"message":"acme/typo is not a valid model ID","code":400}}',
      );

      expect(e.type, CloudErrorType.modelRetired);
    });

    test('reads the message from an OpenAI-style error body', () {
      final e = CloudError.fromResponse(
        'Groq',
        401,
        '{"error":{"message":"Invalid API Key"}}',
      );

      expect(e.message, 'Invalid API Key');
    });

    test('falls back to the raw body, or a placeholder when empty', () {
      expect(
        CloudError.fromResponse('Groq', 500, 'Bad Gateway').message,
        'Bad Gateway',
      );
      expect(CloudError.fromResponse('Groq', 500, '').message, 'Unknown error');
      expect(
        CloudError.fromResponse('Groq', 500, '{"error":"flat"}').message,
        '{"error":"flat"}',
      );
      expect(
        CloudError.fromResponse(
          'Groq',
          500,
          '{"error":{"message":""}}',
        ).message,
        '{"error":{"message":""}}',
      );
    });

    test('a 429 keeps retry-after; other statuses ignore it', () {
      final limited = CloudError.fromResponse(
        'Groq',
        429,
        '{}',
        headers: {'retry-after': '30'},
      );
      final failed = CloudError.fromResponse(
        'Groq',
        500,
        '{}',
        headers: {'retry-after': '30'},
      );
      final unparsable = CloudError.fromResponse(
        'Groq',
        429,
        '{}',
        headers: {'retry-after': 'soon'},
      );

      expect(limited.retryAfter, const Duration(seconds: 30));
      expect(failed.retryAfter, isNull);
      expect(unparsable.retryAfter, isNull);
    });
  });

  test('network() is a networkError with the reason', () {
    final e = CloudError.network('Groq', 'Request timed out');

    expect(e.type, CloudErrorType.networkError);
    expect(e.message, 'Request timed out');
    expect(e.service, 'Groq');
    expect(e.retryAfter, isNull);
  });
}
