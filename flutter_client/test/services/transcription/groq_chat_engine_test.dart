// HTTP status codes are the subject under test; mocks are rebuilt per test.
// ignore_for_file: no-magic-number, avoid-late-keyword, prefer-match-file-name
import 'dart:convert';

import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/transcription/cloud_error.dart';
import 'package:flutter_client/services/transcription/cloud_http.dart';
import 'package:flutter_client/services/transcription/groq_chat_engine.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class _MockSettingsService extends Mock implements SettingsService {}

void main() {
  late _MockSettingsService settings;
  late List<http.Request> requests;
  late http.Response Function() reply;

  GroqChatEngine engine() => GroqChatEngine(
    settings,
    CloudHttp(
      client: MockClient((request) async {
        requests.add(request);

        return reply();
      }),
    ),
  );

  Future<void> complete(GroqChatEngine chat) => chat.complete(
    systemPrompt: 'Polish it.',
    userContent: '<transcript>\nhi\n</transcript>',
    maxTokens: 256,
    timeout: const Duration(seconds: 5),
  );

  setUp(() {
    settings = _MockSettingsService();
    when(() => settings.cachedGroqApiKey).thenReturn('gsk_chat');
    requests = [];
    reply = () => http.Response(
      '{"choices":[{"message":{"content":"Hi."},"finish_reason":"stop"}]}',
      200,
    );
  });

  test('is the Groq chat engine', () {
    expect(engine().source, TranscriptionSource.groq);
  });

  test('sends the rewrite request Groq expects', () async {
    final result = await engine().complete(
      systemPrompt: 'Polish it.',
      userContent: '<transcript>\nhi\n</transcript>',
      maxTokens: 256,
      timeout: const Duration(seconds: 5),
    );

    final request = requests.single;
    expect(request.url, Uri.parse(AppConstants.groqChatCompletionsEndpoint));
    expect(request.headers['Authorization'], 'Bearer gsk_chat');
    expect(jsonDecode(request.body), {
      'model': AppConstants.groqTransformModel,
      'messages': [
        {'role': 'system', 'content': 'Polish it.'},
        {'role': 'user', 'content': '<transcript>\nhi\n</transcript>'},
      ],
      'temperature': AppConstants.transformTemperature,
      'max_completion_tokens': 256,
      'stream': false,
      'include_reasoning': false,
    });
    expect(result.text, 'Hi.');
    expect(result.finishReason, 'stop');
  });

  test('no key fails before anything is sent', () async {
    when(() => settings.cachedGroqApiKey).thenReturn(null);

    await expectLater(
      complete(engine()),
      throwsA(
        isA<CloudError>()
            .having((e) => e.type, 'type', CloudErrorType.invalidApiKey)
            .having((e) => e.message, 'message', 'No Groq API key configured'),
      ),
    );
    expect(requests, isEmpty);
  });

  test('a 429 carries its retry-after to the caller', () async {
    reply = () => http.Response('{}', 429, headers: {'retry-after': '9'});

    await expectLater(
      complete(engine()),
      throwsA(
        isA<CloudError>()
            .having((e) => e.type, 'type', CloudErrorType.rateLimited)
            .having(
              (e) => e.retryAfter,
              'retryAfter',
              const Duration(seconds: 9),
            ),
      ),
    );
  });
}
