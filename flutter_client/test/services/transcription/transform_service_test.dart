// Token counts and timeouts are the subject under test; fakes are rebuilt
// per test.
// ignore_for_file: no-magic-number, avoid-late-keyword, prefer-match-file-name
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/dictation_profile.dart';
import 'package:flutter_client/logic/models/dictation_profile_spec.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/transcription/chat_engine.dart';
import 'package:flutter_client/services/transcription/cloud_error.dart';
import 'package:flutter_client/services/transcription/transform_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSettingsService extends Mock implements SettingsService {}

class _MockProfile extends Mock implements DictationProfileSpec {}

/// One recorded [ChatEngine.complete] call.
typedef _Call = ({
  String systemPrompt,
  String userContent,
  int maxTokens,
  Duration timeout,
});

/// Records each request and answers with [reply].
class _FakeChat implements ChatEngine {
  _FakeChat(this.source);

  @override
  final TranscriptionSource source;

  final List<_Call> calls = [];
  Future<ChatResult> Function() reply = () async =>
      const ChatResult(text: 'Polished text here.', finishReason: 'stop');

  @override
  Future<ChatResult> complete({
    required String systemPrompt,
    required String userContent,
    required int maxTokens,
    required Duration timeout,
  }) {
    calls.add((
      systemPrompt: systemPrompt,
      userContent: userContent,
      maxTokens: maxTokens,
      timeout: timeout,
    ));

    return reply();
  }
}

void main() {
  const input = 'polished text here';
  late _MockSettingsService settings;
  late _FakeChat groq;
  late _FakeChat openRouter;
  late TransformService service;

  void use(TranscriptionSource source) =>
      when(() => settings.transcriptionSource).thenReturn(source);

  CloudError limited(int seconds) => CloudError(
    service: 'Groq',
    type: CloudErrorType.rateLimited,
    message: 'slow down',
    retryAfter: Duration(seconds: seconds),
  );

  setUp(() {
    settings = _MockSettingsService();
    groq = _FakeChat(TranscriptionSource.groq);
    openRouter = _FakeChat(TranscriptionSource.openRouter);
    service = TransformService(settings, [groq, openRouter]);
    use(TranscriptionSource.groq);
    when(() => settings.hasCustomRewriteModel).thenReturn(false);
  });

  group('routing', () {
    test('raw text passes through without calling anything', () async {
      expect(await service.transform(input, DictationProfile.raw), input);
      expect(groq.calls, isEmpty);
    });

    test('uses the active source’s engine', () async {
      use(TranscriptionSource.openRouter);

      await service.transform(input, DictationProfile.clean);

      expect(openRouter.calls, hasLength(1));
      expect(groq.calls, isEmpty);
    });

    test('the server source can’t polish', () {
      use(TranscriptionSource.server);

      expect(
        () => service.transform(input, DictationProfile.clean),
        throwsA(
          isA<CloudError>()
              .having((e) => e.type, 'type', CloudErrorType.badRequest)
              .having((e) => e.service, 'service', 'WhisperDoc server')
              .having((e) => e.message, 'message', 'This style can’t run here'),
        ),
      );
    });

    test('a style without a prompt fails before any request', () {
      final blank = _MockProfile();
      when(() => blank.requiresLlm).thenReturn(true);
      when(() => blank.systemPrompt).thenReturn('  \n ');

      expect(
        () => service.transform(input, blank),
        throwsA(
          isA<CloudError>().having(
            (e) => e.type,
            'type',
            CloudErrorType.badRequest,
          ),
        ),
      );
      expect(groq.calls, isEmpty);
    });
  });

  group('the request', () {
    test('wraps the transcript and sends the style’s prompt', () async {
      final result = await service.transform(input, DictationProfile.clean);

      final call = groq.calls.single;
      expect(result, 'Polished text here.');
      expect(call.systemPrompt, DictationProfile.clean.systemPrompt);
      expect(call.userContent, '<transcript>\n$input\n</transcript>');
    });

    test('a short transcript gets the minimum budget', () async {
      await service.transform('one two', DictationProfile.clean);

      final call = groq.calls.single;
      expect(call.maxTokens, AppConstants.transformMinCompletionTokens);
      expect(
        call.timeout,
        AppConstants.transformTimeoutBase +
            AppConstants.transformTimeoutPerWord * 2,
      );
    });

    test('tokens and time scale with a long transcript, up to a cap', () async {
      // 200 words, 999 characters: 333 tokens estimated, 666 allowed, and
      // 6.5 s, under the 8 s cap.
      final medium = List.filled(200, 'word').join(' ');
      groq.reply = () async => ChatResult(text: medium, finishReason: 'stop');
      await service.transform(medium, DictationProfile.clean);
      expect(groq.calls.last.maxTokens, 666);
      expect(
        groq.calls.last.timeout,
        AppConstants.transformTimeoutBase +
            AppConstants.transformTimeoutPerWord * 200,
      );

      final huge = List.filled(5000, 'word').join(' ');
      groq.reply = () async => ChatResult(text: huge, finishReason: 'stop');
      await service.transform(huge, DictationProfile.clean);
      expect(
        groq.calls.last.maxTokens,
        AppConstants.transformMaxCompletionTokens,
      );
      expect(groq.calls.last.timeout, AppConstants.transformTimeoutMax);
    });
  });

  group('the answer', () {
    test('is guarded and sanitized', () async {
      groq.reply = () async => const ChatResult(
        text: '<think>hmm</think>“Polished” text\u0007 here.',
        finishReason: 'stop',
      );

      expect(
        await service.transform(input, DictationProfile.clean),
        '"Polished" text here.',
      );
    });

    test('a rewrite cut off by the token cap is rejected', () {
      groq.reply = () async =>
          const ChatResult(text: 'Polished text', finishReason: 'length');

      expect(
        () => service.transform(input, DictationProfile.clean),
        throwsA(
          isA<CloudError>()
              .having((e) => e.type, 'type', CloudErrorType.unknown)
              .having(
                (e) => e.message,
                'message',
                'Transform output truncated by token cap',
              ),
        ),
      );
    });

    test('a rewrite the guard rejects is an error, not pasted', () {
      groq.reply = () async =>
          const ChatResult(text: '<think>only thoughts</think>');

      expect(
        () => service.transform(input, DictationProfile.clean),
        throwsA(
          isA<CloudError>().having(
            (e) => e.message,
            'message',
            'Transform output rejected by guard',
          ),
        ),
      );
    });
  });

  group('the style model', () {
    test(
      'a missing rewrite model is the service’s problem, not a choice',
      () async {
        final seen = <CloudErrorType>[];
        for (final type in [
          CloudErrorType.modelRetired,
          CloudErrorType.modelUnavailable,
        ]) {
          groq.reply = () async =>
              throw CloudError(service: 'Groq', type: type, message: 'gone');
          try {
            await service.transform(input, DictationProfile.clean);
          } on CloudError catch (e) {
            seen.add(e.type);
            expect(e.userMessage, 'Groq is temporarily unavailable.');
            expect(e.message, 'gone');
          }
        }

        expect(seen, List.filled(2, CloudErrorType.serverError));
      },
    );

    test(
      'a rewrite model the user chose that is gone says so, to choose again',
      () async {
        use(TranscriptionSource.openRouter);
        when(() => settings.hasCustomRewriteModel).thenReturn(true);
        openRouter.reply = () async => throw const CloudError(
          service: 'OpenRouter',
          type: CloudErrorType.modelRetired,
          message: 'gone',
        );

        await expectLater(
          service.transform(input, DictationProfile.clean),
          throwsA(
            isA<CloudError>().having(
              (e) => e.type,
              'type',
              CloudErrorType.modelRetired,
            ),
          ),
        );
      },
    );

    test('other errors pass through unchanged', () async {
      groq.reply = () async => throw const CloudError(
        service: 'Groq',
        type: CloudErrorType.insufficientCredits,
        message: 'no credits',
      );

      await expectLater(
        service.transform(input, DictationProfile.clean),
        throwsA(
          isA<CloudError>().having(
            (e) => e.type,
            'type',
            CloudErrorType.insufficientCredits,
          ),
        ),
      );
    });
  });

  group('rate limits', () {
    test('a 429 holds that source off until its retry-after', () async {
      groq.reply = () async => throw limited(30);
      await expectLater(
        service.transform(input, DictationProfile.clean),
        throwsA(isA<CloudError>()),
      );
      groq.reply = () async => const ChatResult(text: 'Polished text here.');

      await expectLater(
        service.transform(input, DictationProfile.clean),
        throwsA(
          isA<CloudError>()
              .having((e) => e.type, 'type', CloudErrorType.rateLimited)
              .having(
                (e) => e.message,
                'message',
                'Groq rate limit cooldown active',
              )
              .having(
                (e) => e.retryAfter?.inSeconds,
                'retryAfter',
                inInclusiveRange(28, 30),
              ),
        ),
      );
      expect(groq.calls, hasLength(1));
    });

    test('one source’s cool-down does not block another', () async {
      groq.reply = () async => throw limited(30);
      await expectLater(
        service.transform(input, DictationProfile.clean),
        throwsA(isA<CloudError>()),
      );

      use(TranscriptionSource.openRouter);

      expect(
        await service.transform(input, DictationProfile.clean),
        'Polished text here.',
      );
    });

    test('a 429 without retry-after sets no cool-down', () async {
      groq.reply = () async => throw const CloudError(
        service: 'Groq',
        type: CloudErrorType.rateLimited,
        message: 'slow down',
      );
      await expectLater(
        service.transform(input, DictationProfile.clean),
        throwsA(isA<CloudError>()),
      );
      groq.reply = () async => const ChatResult(text: 'Polished text here.');

      expect(
        await service.transform(input, DictationProfile.clean),
        'Polished text here.',
      );
    });
  });
}
