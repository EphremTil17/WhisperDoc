import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/services/transcription/groq_chat_client.dart';
import 'package:flutter_client/services/transcription/groq_error.dart';

void main() {
  const statusOk = 200;
  const statusUnauthorized = 401;
  const statusRateLimited = 429;
  const statusServerError = 500;
  const retryAfterSeconds = 15;
  const defaultMaxTokens = 128;
  const shortMaxTokens = 64;
  const fullMaxTokens = 256;
  const expectedMessageCount = 2;

  group('GroqChatClient', () {
    test('returns completion text on 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          AppConstants.groqChatCompletionsEndpoint,
        );
        expect(request.headers['Authorization'], 'Bearer test-api-key');
        expect(request.headers['Content-Type'], contains('application/json'));

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model'], AppConstants.groqTransformModel);
        expect(body['stream'], false);
        expect(body['include_reasoning'], false);
        expect(body['max_completion_tokens'], fullMaxTokens);

        final messages = (body['messages'] as List<Object?>)
            .cast<Map<String, dynamic>>();
        expect(messages.length, expectedMessageCount);
        expect(messages.first['role'], 'system');
        expect(messages.first['content'], 'System prompt here');
        expect(messages[1]['role'], 'user');
        expect(messages[1]['content'], '<transcript>\nRaw text\n</transcript>');

        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'Cleaned text'},
              },
            ],
          }),
          statusOk,
          headers: {'x-ratelimit-remaining-tokens': '500000'},
        );
      });

      final client = GroqChatClient(client: mockClient);
      final result = await client.complete(
        apiKey: 'test-api-key',
        systemPrompt: 'System prompt here',
        userContent: 'Raw text',
        maxCompletionTokens: fullMaxTokens,
        timeout: const Duration(seconds: 3),
      );

      expect(result.text, 'Cleaned text');
    });

    test('parses finish_reason from response choices', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'role': 'assistant', 'content': 'Partial text...'},
                'finish_reason': 'length',
              },
            ],
          }),
          statusOk,
        );
      });

      final client = GroqChatClient(client: mockClient);
      final result = await client.complete(
        apiKey: 'test-api-key',
        systemPrompt: 'System prompt',
        userContent: 'Long raw text',
        maxCompletionTokens: shortMaxTokens,
        timeout: const Duration(seconds: 3),
      );

      expect(result.text, 'Partial text...');
      expect(result.finishReason, 'length');
    });

    test(
      'finishReason is null when finish_reason is omitted in choice',
      () async {
        final mockClient = MockClient((_) async {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'role': 'assistant', 'content': 'Complete text'},
                },
              ],
            }),
            statusOk,
          );
        });

        final client = GroqChatClient(client: mockClient);
        final result = await client.complete(
          apiKey: 'test-api-key',
          systemPrompt: 'System prompt',
          userContent: 'Raw text',
          maxCompletionTokens: shortMaxTokens,
          timeout: const Duration(seconds: 3),
        );

        expect(result.text, 'Complete text');
        expect(result.finishReason, isNull);
      },
    );

    test('throws invalidApiKey on 401', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          '{"error": {"message": "Invalid API Key"}}',
          statusUnauthorized,
        );
      });

      final client = GroqChatClient(client: mockClient);

      expect(
        () => client.complete(
          apiKey: 'bad-key',
          systemPrompt: 'sys',
          userContent: 'usr',
          maxCompletionTokens: defaultMaxTokens,
          timeout: const Duration(seconds: 2),
        ),
        throwsA(
          isA<GroqError>().having(
            (e) => e.type,
            'type',
            GroqErrorType.invalidApiKey,
          ),
        ),
      );
    });

    test('throws rateLimited on 429 with retry-after', () async {
      final mockClient = MockClient((_) async {
        return http.Response(
          '{"error": {"message": "Rate limit exceeded"}}',
          statusRateLimited,
          headers: {'retry-after': '$retryAfterSeconds'},
        );
      });

      final client = GroqChatClient(client: mockClient);

      try {
        await client.complete(
          apiKey: 'test-key',
          systemPrompt: 'sys',
          userContent: 'usr',
          maxCompletionTokens: defaultMaxTokens,
          timeout: const Duration(seconds: 2),
        );
        fail('Should have thrown GroqError');
      } on GroqError catch (e) {
        expect(e.type, GroqErrorType.rateLimited);
        expect(e.retryAfter, const Duration(seconds: retryAfterSeconds));
      }
    });

    test('throws serverError on 500', () async {
      final mockClient = MockClient((_) async {
        return http.Response('Internal Server Error', statusServerError);
      });

      final client = GroqChatClient(client: mockClient);

      expect(
        () => client.complete(
          apiKey: 'test-key',
          systemPrompt: 'sys',
          userContent: 'usr',
          maxCompletionTokens: defaultMaxTokens,
          timeout: const Duration(seconds: 2),
        ),
        throwsA(
          isA<GroqError>().having(
            (e) => e.type,
            'type',
            GroqErrorType.serverError,
          ),
        ),
      );
    });

    test('maps SocketException to networkError', () async {
      final mockClient = MockClient((_) async {
        throw const SocketException('Connection refused');
      });

      final client = GroqChatClient(client: mockClient);

      expect(
        () => client.complete(
          apiKey: 'test-key',
          systemPrompt: 'sys',
          userContent: 'usr',
          maxCompletionTokens: defaultMaxTokens,
          timeout: const Duration(seconds: 2),
        ),
        throwsA(
          isA<GroqError>().having(
            (e) => e.type,
            'type',
            GroqErrorType.networkError,
          ),
        ),
      );
    });

    test('maps TimeoutException to networkError', () async {
      final mockClient = MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));

        return http.Response('{"text": "late"}', statusOk);
      });

      final client = GroqChatClient(client: mockClient);

      expect(
        () => client.complete(
          apiKey: 'test-key',
          systemPrompt: 'sys',
          userContent: 'usr',
          maxCompletionTokens: defaultMaxTokens,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(
          isA<GroqError>()
              .having((e) => e.type, 'type', GroqErrorType.networkError)
              .having((e) => e.message, 'message', contains('timed out')),
        ),
      );
    });
  });
}
