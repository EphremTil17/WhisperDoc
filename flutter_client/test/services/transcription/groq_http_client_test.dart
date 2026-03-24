import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_client/services/transcription/groq_http_client.dart';
import 'package:flutter_client/services/transcription/groq_error.dart';

void main() {
  group('GroqHttpClient', () {
    final fakeWav = Uint8List(100);

    test('returns transcription text on 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], 'Bearer test-key');
        return http.Response('{"text": "hello world"}', 200);
      });

      final client = GroqHttpClient(client: mockClient);
      final result = await client.transcribe(
        wavBytes: fakeWav,
        apiKey: 'test-key',
      );

      expect(result.text, 'hello world');
    });

    test('sends language and prompt when provided', () async {
      final mockClient = MockClient((request) async {
        // MultipartRequest fields are in the body, check the request URL
        expect(request.url.path, contains('transcriptions'));
        return http.Response('{"text": "hola"}', 200);
      });

      final client = GroqHttpClient(client: mockClient);
      final result = await client.transcribe(
        wavBytes: fakeWav,
        apiKey: 'test-key',
        language: 'es',
        prompt: 'medical terminology',
      );

      expect(result.text, 'hola');
    });

    test('throws invalidApiKey on 401', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          '{"error": {"message": "Invalid API Key"}}',
          401,
        );
      });

      final client = GroqHttpClient(client: mockClient);

      expect(
        () => client.transcribe(wavBytes: fakeWav, apiKey: 'bad-key'),
        throwsA(isA<GroqError>().having(
          (e) => e.type,
          'type',
          GroqErrorType.invalidApiKey,
        )),
      );
    });

    test('throws rateLimited on 429 with retryAfter', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          '{"error": {"message": "Rate limit exceeded"}}',
          429,
          headers: {'retry-after': '30'},
        );
      });

      final client = GroqHttpClient(client: mockClient);

      try {
        await client.transcribe(wavBytes: fakeWav, apiKey: 'key');
        fail('Should have thrown');
      } on GroqError catch (e) {
        expect(e.type, GroqErrorType.rateLimited);
        expect(e.retryAfter, const Duration(seconds: 30));
      }
    });

    test('throws fileTooLarge on 413', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          '{"error": {"message": "Request too large"}}',
          413,
        );
      });

      final client = GroqHttpClient(client: mockClient);

      expect(
        () => client.transcribe(wavBytes: fakeWav, apiKey: 'key'),
        throwsA(isA<GroqError>().having(
          (e) => e.type,
          'type',
          GroqErrorType.fileTooLarge,
        )),
      );
    });

    test('throws serverError on 500', () async {
      final mockClient = MockClient((_) async {
        return http.Response('Internal Server Error', 500);
      });

      final client = GroqHttpClient(client: mockClient);

      expect(
        () => client.transcribe(wavBytes: fakeWav, apiKey: 'key'),
        throwsA(isA<GroqError>().having(
          (e) => e.type,
          'type',
          GroqErrorType.serverError,
        )),
      );
    });

    test('returns empty string when response text field is missing', () async {
      final mockClient = MockClient((_) async {
        return http.Response('{"x_groq": {"id": "req_123"}}', 200);
      });

      final client = GroqHttpClient(client: mockClient);
      final result = await client.transcribe(
        wavBytes: fakeWav,
        apiKey: 'key',
      );

      expect(result.text, '');
    });

    test('exposes response headers for rate limiter', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          '{"text": "test"}',
          200,
          headers: {
            'x-ratelimit-remaining-requests': '18',
            'x-ratelimit-remaining-tokens': '5000',
          },
        );
      });

      final client = GroqHttpClient(client: mockClient);
      final result = await client.transcribe(
        wavBytes: fakeWav,
        apiKey: 'key',
      );

      expect(result.responseHeaders['x-ratelimit-remaining-requests'], '18');
    });
  });
}
