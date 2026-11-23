// ignore_for_file: prefer-match-file-name, avoid-late-keyword
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/services/transcription/groq_transcription_service.dart';
import 'package:flutter_client/services/transcription/groq_error.dart';
import 'package:flutter_client/services/utility/settings_service.dart';

import 'package:flutter_client/services/transcription/groq_http_client.dart';

class _MockSettingsService extends Mock implements SettingsService {}

class _MockGroqHttpClient extends Mock implements GroqHttpClient {}

void main() {
  // Named constants for chunk sizes used across tests.
  const chunkSmall = 100;
  const chunkLarge = 200;
  const chunkSmallPlusLarge = 300;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  group('GroqTranscriptionService', () {
    late GroqTranscriptionService service;
    late _MockSettingsService mockSettings;

    setUp(() {
      mockSettings = _MockSettingsService();
      when(() => mockSettings.cachedGroqApiKey).thenReturn('test-groq-key');
      when(() => mockSettings.groqLanguage).thenReturn('');
      when(() => mockSettings.groqPrompt).thenReturn('');
      when(() => mockSettings.groqModel).thenReturn('whisper-large-v3-turbo');

      service = GroqTranscriptionService(mockSettings);
    });

    test('starts in idle status', () {
      expect(service.status, GroqTranscriptionStatus.idle);
      expect(service.bufferSizeBytes, 0);
    });

    test('hasValidCredentials is true when key is set', () {
      expect(service.hasValidCredentials, isTrue);
    });

    test('hasValidCredentials is false when key is null', () {
      when(() => mockSettings.cachedGroqApiKey).thenReturn(null);
      final noKeyService = GroqTranscriptionService(mockSettings);

      expect(noKeyService.hasValidCredentials, isFalse);
    });

    test('hasValidCredentials is false when key is empty', () {
      when(() => mockSettings.cachedGroqApiKey).thenReturn('');
      final emptyKeyService = GroqTranscriptionService(mockSettings);

      expect(emptyKeyService.hasValidCredentials, isFalse);
    });

    test('bufferAudioChunk transitions to buffering', () {
      service.bufferAudioChunk(Uint8List(chunkSmall));

      expect(service.status, GroqTranscriptionStatus.buffering);
      expect(service.bufferSizeBytes, chunkSmall);
    });

    test('bufferAudioChunk accumulates multiple chunks', () {
      service.bufferAudioChunk(Uint8List(chunkSmall));
      service.bufferAudioChunk(Uint8List(chunkLarge));

      expect(service.bufferSizeBytes, chunkSmallPlusLarge);
    });

    test('clearBuffer resets to idle', () {
      service.bufferAudioChunk(Uint8List(chunkSmall));
      service.clearBuffer();

      expect(service.status, GroqTranscriptionStatus.idle);
      expect(service.bufferSizeBytes, 0);
    });

    test('finalizeAndTranscribe throws when buffer is empty', () {
      expect(
        () => service.finalizeAndTranscribe(),
        throwsA(
          isA<GroqError>().having(
            (e) => e.type,
            'type',
            GroqErrorType.badRequest,
          ),
        ),
      );
    });

    test(
      'finalizeAndTranscribe passes model from settings to http client',
      () async {
        when(() => mockSettings.groqModel).thenReturn('whisper-large-v3');
        final mockHttpClient = _MockGroqHttpClient();
        when(
          () => mockHttpClient.transcribe(
            wavBytes: any(named: 'wavBytes'),
            apiKey: any(named: 'apiKey'),
            model: 'whisper-large-v3',
            language: any(named: 'language'),
            prompt: any(named: 'prompt'),
          ),
        ).thenAnswer(
          (_) async => const GroqTranscriptionResult(
            text: 'transcribed accurately',
            responseHeaders: {},
          ),
        );

        final customService = GroqTranscriptionService(
          mockSettings,
          httpClient: mockHttpClient,
        );
        customService.bufferAudioChunk(Uint8List(chunkSmall));
        final text = await customService.finalizeAndTranscribe();

        expect(text, 'transcribed accurately');
        verify(
          () => mockHttpClient.transcribe(
            wavBytes: any(named: 'wavBytes'),
            apiKey: 'test-groq-key',
            model: 'whisper-large-v3',
            language: null,
            prompt: null,
          ),
        ).called(1);
      },
    );
  });

  group('GroqTranscriptionService limits and failures', () {
    late _MockSettingsService settings;
    late _MockGroqHttpClient http;
    late GroqTranscriptionService service;

    void stubTranscribe(Future<GroqTranscriptionResult> Function() answer) {
      when(
        () => http.transcribe(
          wavBytes: any(named: 'wavBytes'),
          apiKey: any(named: 'apiKey'),
          model: any(named: 'model'),
          language: any(named: 'language'),
          prompt: any(named: 'prompt'),
        ),
      ).thenAnswer((_) => answer());
    }

    int transcribeCalls() => verify(
      () => http.transcribe(
        wavBytes: any(named: 'wavBytes'),
        apiKey: any(named: 'apiKey'),
        model: any(named: 'model'),
        language: any(named: 'language'),
        prompt: any(named: 'prompt'),
      ),
    ).callCount;

    Matcher groqError(GroqErrorType type) =>
        throwsA(isA<GroqError>().having((e) => e.type, 'type', type));

    setUp(() {
      settings = _MockSettingsService();
      when(() => settings.cachedGroqApiKey).thenReturn('gsk_test');
      when(() => settings.groqLanguage).thenReturn('en');
      when(() => settings.groqPrompt).thenReturn('Dr. Abebe');
      when(() => settings.groqModel).thenReturn('whisper-large-v3-turbo');
      http = _MockGroqHttpClient();
      when(() => http.dispose()).thenReturn(null);
      stubTranscribe(
        () async => const GroqTranscriptionResult(
          text: 'hello world',
          responseHeaders: {},
        ),
      );
      service = GroqTranscriptionService(settings, httpClient: http);
    });

    test('sends a WAV of the buffered audio with every hint', () async {
      service.bufferAudioChunk(Uint8List.fromList('ab'.codeUnits));
      service.bufferAudioChunk(Uint8List.fromList('cd'.codeUnits));

      await service.finalizeAndTranscribe();

      final sent =
          verify(
                () => http.transcribe(
                  wavBytes: captureAny(named: 'wavBytes'),
                  apiKey: 'gsk_test',
                  model: 'whisper-large-v3-turbo',
                  language: 'en',
                  prompt: 'Dr. Abebe',
                ),
              ).captured.single
              as Uint8List;
      const header = 'RIFF';
      const pcm = 'abcd';
      expect(String.fromCharCodes(sent.sublist(0, header.length)), header);
      expect(String.fromCharCodes(sent.sublist(sent.length - pcm.length)), pcm);
    });

    test('a success returns sanitized text and empties the buffer', () async {
      stubTranscribe(
        () async => const GroqTranscriptionResult(
          text: '\x1B[31mhello\x1B[0m world',
          responseHeaders: {},
        ),
      );
      service.bufferAudioChunk(Uint8List(chunkSmall));

      final text = await service.finalizeAndTranscribe();

      expect(text, 'hello world');
      expect(service.bufferSizeBytes, 0);
      expect(service.status, GroqTranscriptionStatus.idle);
    });

    test('the buffer takes audio up to its ceiling and no more', () {
      expect(
        service.bufferAudioChunk(Uint8List(AppConstants.groqMaxBufferBytes)),
        isTrue,
      );
      expect(service.bufferAudioChunk(Uint8List(1)), isFalse);
      expect(service.bufferSizeBytes, AppConstants.groqMaxBufferBytes);
    });

    test('a missing API key fails without calling Groq', () async {
      when(() => settings.cachedGroqApiKey).thenReturn('');
      service.bufferAudioChunk(Uint8List(chunkSmall));

      await expectLater(
        service.finalizeAndTranscribe(),
        groqError(GroqErrorType.invalidApiKey),
      );
      expect(service.status, GroqTranscriptionStatus.error);
      expect(service.bufferSizeBytes, 0);
      verifyNever(
        () => http.transcribe(
          wavBytes: any(named: 'wavBytes'),
          apiKey: any(named: 'apiKey'),
          model: any(named: 'model'),
          language: any(named: 'language'),
          prompt: any(named: 'prompt'),
        ),
      );
    });

    test('an unsupported language fails without calling Groq', () async {
      when(() => settings.groqLanguage).thenReturn('klingon');
      service.bufferAudioChunk(Uint8List(chunkSmall));

      await expectLater(
        service.finalizeAndTranscribe(),
        groqError(GroqErrorType.badRequest),
      );
      expect(service.status, GroqTranscriptionStatus.error);
      expect(service.bufferSizeBytes, 0);
    });

    test('an unexpected failure becomes an unknown GroqError', () async {
      stubTranscribe(() async => throw const SocketException('reset'));
      service.bufferAudioChunk(Uint8List(chunkSmall));

      await expectLater(
        service.finalizeAndTranscribe(),
        groqError(GroqErrorType.unknown),
      );
      expect(service.status, GroqTranscriptionStatus.error);
      expect(service.bufferSizeBytes, 0);
    });

    test('a server retry-after holds off the next request locally', () async {
      stubTranscribe(
        () async => throw const GroqError(
          type: GroqErrorType.rateLimited,
          message: 'Too many requests',
          retryAfter: Duration(minutes: 1),
        ),
      );
      service.bufferAudioChunk(Uint8List(chunkSmall));
      await expectLater(
        service.finalizeAndTranscribe(),
        groqError(GroqErrorType.rateLimited),
      );

      service.bufferAudioChunk(Uint8List(chunkSmall));
      await expectLater(
        service.finalizeAndTranscribe(),
        throwsA(
          isA<GroqError>()
              .having((e) => e.message, 'message', 'Local rate limit reached')
              .having((e) => e.retryAfter, 'retryAfter', isNot(Duration.zero)),
        ),
      );
      expect(transcribeCalls(), 1);
      expect(service.bufferSizeBytes, 0);
    });

    test('the free-tier requests-per-minute limit is enforced', () async {
      for (var i = 0; i < AppConstants.groqMaxRpm; i++) {
        service.bufferAudioChunk(Uint8List(chunkSmall));
        await service.finalizeAndTranscribe();
      }

      service.bufferAudioChunk(Uint8List(chunkSmall));

      await expectLater(
        service.finalizeAndTranscribe(),
        groqError(GroqErrorType.rateLimited),
      );
      expect(transcribeCalls(), AppConstants.groqMaxRpm);
    });

    test('dispose closes the HTTP client', () {
      service.dispose();

      final closed = verify(() => http.dispose());
      expect(closed.callCount, 1);
    });
  });
}
