// Mocks are rebuilt per test.
// ignore_for_file: avoid-late-keyword, prefer-match-file-name, no-magic-number
import 'dart:convert';

import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/transcription/cloud_error.dart';
import 'package:flutter_client/services/transcription/cloud_http.dart';
import 'package:flutter_client/services/transcription/open_router_chat_engine.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class _MockSettingsService extends Mock implements SettingsService {}

void main() {
  late _MockSettingsService settings;
  late List<http.Request> requests;
  late http.Response reply;

  OpenRouterChatEngine engine() => OpenRouterChatEngine(
    settings,
    CloudHttp(
      client: MockClient((request) async {
        requests.add(request);

        return reply;
      }),
    ),
  );

  http.Response answer(String content) => http.Response(
    jsonEncode({
      'choices': [
        {
          'message': {'content': content},
          'finish_reason': 'stop',
        },
      ],
    }),
    200,
  );

  http.Response failure(int status, String message) => http.Response(
    jsonEncode({
      'error': {'message': message},
    }),
    status,
  );

  Map<String, dynamic> sentBody() =>
      jsonDecode(requests.single.body) as Map<String, dynamic>;

  Future<Map<String, dynamic>> send() async {
    await engine().complete(
      systemPrompt: 'Tidy.',
      userContent: '<transcript>\nok\n</transcript>',
      maxTokens: 300,
      timeout: const Duration(seconds: 5),
    );

    return sentBody();
  }

  setUp(() {
    settings = _MockSettingsService();
    when(() => settings.cachedOpenRouterApiKey).thenReturn('sk-or-chat');
    when(() => settings.openRouterZdr).thenReturn(true);
    when(() => settings.openRouterRewriteModel)
        .thenReturn(AppConstants.openRouterTransformModel);
    requests = [];
    reply = http.Response(
      '{"choices":[{"message":{"content":"Done."},'
      '"finish_reason":"length"}]}',
      200,
    );
  });

  test('is the OpenRouter chat engine', () {
    expect(engine().source, TranscriptionSource.openRouter);
  });

  test(
    'asks for the rewrite with no reasoning, from a quick ZDR host',
    () async {
      final body = await send();

      final request = requests.single;
      expect(request.url, Uri.parse(AppConstants.openRouterChatEndpoint));
      expect(request.headers['Authorization'], 'Bearer sk-or-chat');
      expect(body, {
        'model': AppConstants.openRouterTransformModel,
        'messages': [
          {'role': 'system', 'content': 'Tidy.'},
          {'role': 'user', 'content': '<transcript>\nok\n</transcript>'},
        ],
        'temperature': AppConstants.transformTemperature,
        'max_tokens': 300,
        'stream': false,
        'reasoning': {'enabled': false},
        'provider': {
          'zdr': true,
          'sort': 'latency',
          'preferred_min_throughput': {
            'p50': AppConstants.openRouterRewriteMinThroughput,
          },
        },
      });
    },
  );

  test('rewrites with the model chosen in Account', () async {
    when(() => settings.openRouterRewriteModel)
        .thenReturn('deepseek/deepseek-v4.1-flash');

    final body = await send();

    expect(body['model'], 'deepseek/deepseek-v4.1-flash');
  });

  test(
    'without zero data retention only the speed preferences are sent',
    () async {
      when(() => settings.openRouterZdr).thenReturn(false);

      final body = await send();

      expect(body['provider'], {
        'sort': 'latency',
        'preferred_min_throughput': {
          'p50': AppConstants.openRouterRewriteMinThroughput,
        },
      });
    },
  );

  test('returns the text and the finish reason', () async {
    final result = await engine().complete(
      systemPrompt: 's',
      userContent: 'u',
      maxTokens: 10,
      timeout: const Duration(seconds: 5),
    );

    expect(result.text, 'Done.');
    expect(result.finishReason, 'length');
  });

  test('no key fails before anything is sent', () async {
    when(() => settings.cachedOpenRouterApiKey).thenReturn('');

    await expectLater(
      engine().complete(
        systemPrompt: 's',
        userContent: 'u',
        maxTokens: 10,
        timeout: const Duration(seconds: 5),
      ),
      throwsA(
        isA<CloudError>()
            .having((e) => e.type, 'type', CloudErrorType.invalidApiKey)
            .having(
              (e) => e.message,
              'message',
              'No OpenRouter API key configured',
            ),
      ),
    );
    expect(requests, isEmpty);
  });

  group('checking a rewrite model', () {
    test('sends it a tiny rewrite on the same terms, and passes', () async {
      reply = answer('ok');

      final problem = await engine().checkModel('anthropic/claude-haiku-5.5');

      final body = sentBody();
      expect(problem, isNull);
      expect(body['model'], 'anthropic/claude-haiku-5.5');
      expect(body['max_tokens'], AppConstants.openRouterRewriteCheckTokens);
      expect(body['reasoning'], {'enabled': false});
      expect((body['provider'] as Map<String, dynamic>)['zdr'], isTrue);
    });

    test('says why a model can’t serve the styles', () async {
      final cases = {
        failure(400, 'acme/x is not a valid model ID'):
            'OpenRouter has no model by this id.',
        failure(404, 'No endpoints found matching your data policy'):
            'No host of this model keeps zero data.',
        failure(
          400,
          'Reasoning is mandatory for this endpoint and cannot be disabled.',
        ): 'This model always reasons first, which is too slow for styles.',
        failure(402, 'Insufficient credits'):
            'Your OpenRouter credits ran out. Add credits to keep dictating.',
        answer('   '): 'This model answered with no text, so it can’t rewrite.',
      };
      final said = <String?>[];
      for (final response in cases.keys) {
        reply = response;
        said.add(await engine().checkModel('acme/x'));
      }

      expect(said, cases.values.toList());
    });

    test(
      'without zero data retention, a model with no host is unserved',
      () async {
        when(() => settings.openRouterZdr).thenReturn(false);
        reply = failure(404, 'No endpoints found');

        final problem = await engine().checkModel('acme/x');

        expect(problem, 'No host serves this model right now.');
      },
    );

    test('no key says so, with nothing sent', () async {
      when(() => settings.cachedOpenRouterApiKey).thenReturn(null);

      final problem = await engine().checkModel('acme/x');

      expect(problem, 'Invalid OpenRouter API key. Check Account.');
      expect(requests, isEmpty);
    });
  });
}
