// ignore_for_file: avoid-late-keyword, prefer-match-file-name
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/custom_profile.dart';
import 'package:flutter_client/logic/models/dictation_profile.dart';
import 'package:flutter_client/logic/models/dictation_profile_spec.dart';
import 'package:flutter_client/services/transcription/groq_chat_client.dart';
import 'package:flutter_client/services/transcription/groq_error.dart';
import 'package:flutter_client/services/transcription/groq_transform_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';

class _MockSettingsService extends Mock implements SettingsService {}

class _MockGroqChatClient extends Mock implements GroqChatClient {}

void main() {
  setUpAll(() {
    registerFallbackValue(Duration.zero);
  });

  group('GroqTransformService', () {
    late _MockSettingsService mockSettings;
    late _MockGroqChatClient mockChatClient;
    late GroqTransformService service;

    setUp(() {
      mockSettings = _MockSettingsService();
      mockChatClient = _MockGroqChatClient();

      when(() => mockSettings.cachedGroqApiKey).thenReturn('test-groq-key');
      when(
        () => mockSettings.getGroqApiKey(),
      ).thenAnswer((_) async => 'test-groq-key');

      service = GroqTransformService(mockSettings, chatClient: mockChatClient);
    });

    test(
      'raw profile returns input text immediately without calling client',
      () async {
        final result = await service.transform(
          'Verbatim transcript text.',
          DictationProfile.raw,
        );

        expect(result, 'Verbatim transcript text.');
        verifyNever(
          () => mockChatClient.complete(
            apiKey: any(named: 'apiKey'),
            systemPrompt: any(named: 'systemPrompt'),
            userContent: any(named: 'userContent'),
            maxCompletionTokens: any(named: 'maxCompletionTokens'),
            timeout: any(named: 'timeout'),
          ),
        );
      },
    );

    test('throws invalidApiKey if API key is missing or empty', () async {
      when(() => mockSettings.getGroqApiKey()).thenAnswer((_) async => null);

      expect(
        () => service.transform(
          'Sample sentence for testing polish.',
          DictationProfile.clean,
        ),
        throwsA(
          isA<GroqError>().having(
            (e) => e.type,
            'type',
            GroqErrorType.invalidApiKey,
          ),
        ),
      );
      verifyNever(
        () => mockChatClient.complete(
          apiKey: any(named: 'apiKey'),
          systemPrompt: any(named: 'systemPrompt'),
          userContent: any(named: 'userContent'),
          maxCompletionTokens: any(named: 'maxCompletionTokens'),
          timeout: any(named: 'timeout'),
        ),
      );
    });

    test(
      'successful transform cleans, normalizes, and sanitizes output',
      () async {
        when(
          () => mockChatClient.complete(
            apiKey: any(named: 'apiKey'),
            systemPrompt: any(named: 'systemPrompt'),
            userContent: any(named: 'userContent'),
            maxCompletionTokens: any(named: 'maxCompletionTokens'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => const GroqChatResult(
            text: 'Here is the cleaned and polished sentence.',
          ),
        );

        final result = await service.transform(
          'um here is like the cleaned and uh polished sentence you know',
          DictationProfile.clean,
        );

        expect(result, 'Here is the cleaned and polished sentence.');
      },
    );

    test(
      'scales timeout and maxCompletionTokens with input word count',
      () async {
        Duration? capturedTimeout;
        int? capturedMaxTokens;

        when(
          () => mockChatClient.complete(
            apiKey: any(named: 'apiKey'),
            systemPrompt: any(named: 'systemPrompt'),
            userContent: any(named: 'userContent'),
            maxCompletionTokens: any(named: 'maxCompletionTokens'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((invocation) async {
          capturedTimeout = invocation.namedArguments[#timeout] as Duration?;
          capturedMaxTokens =
              invocation.namedArguments[#maxCompletionTokens] as int?;

          return const GroqChatResult(
            text: 'This is a valid response of roughly equal length.',
          );
        });

        // 10 words text
        const tenWords = 'one two three four five six seven eight nine ten';
        await service.transform(tenWords, DictationProfile.clean);

        // base: 1500ms + 10 * 25ms = 1750ms
        const expectedTimeoutMs = 1750;
        expect(capturedTimeout?.inMilliseconds, expectedTimeoutMs);
        expect(
          capturedMaxTokens,
          greaterThanOrEqualTo(AppConstants.groqTransformMinCompletionTokens),
        );
      },
    );

    test(
      '429 rate limit sets cooldown and rejects subsequent calls early',
      () async {
        when(
          () => mockChatClient.complete(
            apiKey: any(named: 'apiKey'),
            systemPrompt: any(named: 'systemPrompt'),
            userContent: any(named: 'userContent'),
            maxCompletionTokens: any(named: 'maxCompletionTokens'),
            timeout: any(named: 'timeout'),
          ),
        ).thenThrow(
          const GroqError(
            type: GroqErrorType.rateLimited,
            message: 'Rate limited',
            retryAfter: Duration(seconds: 10),
          ),
        );

        final throwsRateLimited = throwsA(
          isA<GroqError>().having(
            (e) => e.type,
            'type',
            GroqErrorType.rateLimited,
          ),
        );

        // First call fails and records 429 cooldown
        await expectLater(
          () => service.transform(
            'Sample sentence for testing polish.',
            DictationProfile.clean,
          ),
          throwsRateLimited,
        );

        // Second call fails fast without invoking chat client
        await expectLater(
          () => service.transform(
            'Another sentence during active cooldown.',
            DictationProfile.clean,
          ),
          throwsRateLimited,
        );

        // Client should have only been invoked once
        verify(
          () => mockChatClient.complete(
            apiKey: any(named: 'apiKey'),
            systemPrompt: any(named: 'systemPrompt'),
            userContent: any(named: 'userContent'),
            maxCompletionTokens: any(named: 'maxCompletionTokens'),
            timeout: any(named: 'timeout'),
          ),
        ).called(1);
      },
    );

    test('guard rejection surfaces as typed GroqError', () async {
      when(
        () => mockChatClient.complete(
          apiKey: any(named: 'apiKey'),
          systemPrompt: any(named: 'systemPrompt'),
          userContent: any(named: 'userContent'),
          maxCompletionTokens: any(named: 'maxCompletionTokens'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer(
        (_) async => const GroqChatResult(
          text: '', // Empty output rejected by guard
        ),
      );

      expect(
        () =>
            service.transform('Valid input sentence.', DictationProfile.clean),
        throwsA(
          isA<GroqError>().having(
            (e) => e.message,
            'message',
            contains('rejected by guard'),
          ),
        ),
      );
    });

    test(
      'CustomProfile spec sends its composed prompt as system message',
      () async {
        const customProfile = CustomProfile(
          storageKey: 'custom1',
          name: 'Concise Notes',
          userPrompt: 'Rewrite as concise bullet points.',
        );

        String? capturedSystemPrompt;
        when(
          () => mockChatClient.complete(
            apiKey: any(named: 'apiKey'),
            systemPrompt: any(named: 'systemPrompt'),
            userContent: any(named: 'userContent'),
            maxCompletionTokens: any(named: 'maxCompletionTokens'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer((invocation) async {
          capturedSystemPrompt =
              invocation.namedArguments[#systemPrompt] as String?;

          return const GroqChatResult(
            text: 'Concise notes output.',
            finishReason: 'stop',
          );
        });

        final result = await service.transform(
          'Spoken input needing notes',
          customProfile,
        );

        expect(result, 'Concise notes output.');
        expect(capturedSystemPrompt, contains(DictationProfile.sharedPreamble));
        expect(capturedSystemPrompt, contains('PROFILE: Concise Notes'));
        expect(
          capturedSystemPrompt,
          contains('Rewrite as concise bullet points.'),
        );
      },
    );

    test(
      'profile with empty or whitespace systemPrompt throws GroqError.badRequest',
      () async {
        final mockProfile = _MockDictationProfileSpec();
        when(() => mockProfile.requiresLlm).thenReturn(true);
        when(() => mockProfile.systemPrompt).thenReturn('   \n  ');

        expect(
          () => service.transform('Input text', mockProfile),
          throwsA(
            isA<GroqError>()
                .having((e) => e.type, 'type', GroqErrorType.badRequest)
                .having(
                  (e) => e.message,
                  'message',
                  contains('no system prompt'),
                ),
          ),
        );

        verifyNever(
          () => mockChatClient.complete(
            apiKey: any(named: 'apiKey'),
            systemPrompt: any(named: 'systemPrompt'),
            userContent: any(named: 'userContent'),
            maxCompletionTokens: any(named: 'maxCompletionTokens'),
            timeout: any(named: 'timeout'),
          ),
        );
      },
    );

    test('rejects truncated output when finish_reason is length', () async {
      when(
        () => mockChatClient.complete(
          apiKey: any(named: 'apiKey'),
          systemPrompt: any(named: 'systemPrompt'),
          userContent: any(named: 'userContent'),
          maxCompletionTokens: any(named: 'maxCompletionTokens'),
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer(
        (_) async => const GroqChatResult(
          text:
              'This sentence was cut off mid way through because of token cap',
          finishReason: 'length',
        ),
      );

      expect(
        () => service.transform(
          'Long input that hit token ceiling',
          DictationProfile.clean,
        ),
        throwsA(
          isA<GroqError>().having(
            (e) => e.message,
            'message',
            contains('truncated by token cap'),
          ),
        ),
      );
    });
  });
}

class _MockDictationProfileSpec extends Mock implements DictationProfileSpec {}
