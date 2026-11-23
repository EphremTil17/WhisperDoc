// HTTP status codes and byte sizes are the subject under test; mocks are
// rebuilt per test in setUp and the same engine call repeats on purpose.
// ignore_for_file: no-magic-number, avoid-late-keyword, prefer-match-file-name, prefer-moving-to-variable
import 'dart:typed_data';

import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/transcription/cloud_error.dart';
import 'package:flutter_client/services/transcription/cloud_http.dart';
import 'package:flutter_client/services/transcription/groq_speech_engine.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class _MockSettingsService extends Mock implements SettingsService {}

void main() {
  /// A multipart form field's value, read from the encoded request body.
  String? field(String body, String name) =>
      RegExp('name="$name"\r\n\r\n([^\r]*)\r\n').firstMatch(body)?.group(1);

  final wav = Uint8List.fromList([1, 2, 3, 4]);
  late _MockSettingsService settings;
  late List<http.Request> requests;
  late http.Response Function() reply;

  GroqSpeechEngine engine() => GroqSpeechEngine(
    settings,
    CloudHttp(
      client: MockClient((request) async {
        requests.add(request);

        return reply();
      }),
    ),
  );

  setUp(() {
    settings = _MockSettingsService();
    when(() => settings.cachedGroqApiKey).thenReturn('gsk_test');
    when(() => settings.groqLanguage).thenReturn('');
    when(() => settings.groqPrompt).thenReturn('');
    when(() => settings.groqModel).thenReturn('whisper-large-v3-turbo');
    requests = [];
    reply = () => http.Response('{"text":" hello world","x_groq":{}}', 200);
  });

  test('describes itself as the Groq source with its upload limit', () {
    final groq = engine();

    expect(groq.source, TranscriptionSource.groq);
    expect(groq.maxClipBytes, AppConstants.groqMaxBufferBytes);
    expect(groq.setupProblem, isNull);
    for (final key in ['', null]) {
      when(() => settings.cachedGroqApiKey).thenReturn(key);
      expect(
        groq.setupProblem,
        'Add your Groq API key in Account.',
        reason: '$key',
      );
    }
  });

  test('warms the connection to Groq’s origin', () async {
    engine().warmUp();
    await pumpEventQueue();

    expect(requests.single.method, 'HEAD');
    expect(requests.single.url, Uri.parse(AppConstants.groqOrigin));
  });

  test('uploads the WAV as multipart with the model and no hints', () async {
    final text = await engine().transcribe(wav);

    final request = requests.single;
    expect(text, ' hello world');
    expect(request.method, 'POST');
    expect(request.url, Uri.parse(AppConstants.groqTranscriptionEndpoint));
    expect(request.headers['Authorization'], 'Bearer gsk_test');
    expect(request.headers['content-type'], startsWith('multipart/form-data'));
    final body = String.fromCharCodes(request.bodyBytes);
    expect(field(body, 'model'), 'whisper-large-v3-turbo');
    expect(field(body, 'response_format'), 'json');
    expect(field(body, 'temperature'), '0');
    expect(field(body, 'language'), isNull);
    expect(field(body, 'prompt'), isNull);
    expect(body, contains('filename="audio.wav"'));
    expect(body, contains('content-type: audio/wav'));
    expect(body, contains(String.fromCharCodes(wav)));
  });

  test('sends the language and the words to expect when set', () async {
    when(() => settings.groqLanguage).thenReturn('es');
    when(() => settings.groqPrompt).thenReturn('Siobhan, Kubernetes');
    when(() => settings.groqModel).thenReturn('whisper-large-v3');

    await engine().transcribe(wav);

    final body = String.fromCharCodes(requests.single.bodyBytes);
    expect(field(body, 'language'), 'es');
    expect(field(body, 'prompt'), 'Siobhan, Kubernetes');
    expect(field(body, 'model'), 'whisper-large-v3');
  });

  test('a reply without text is an unknown error', () async {
    for (final body in ['{"x_groq":{}}', 'not json', '[]']) {
      reply = () => http.Response(body, 200);

      await expectLater(
        engine().transcribe(wav),
        throwsA(
          isA<CloudError>()
              .having((e) => e.type, 'type', CloudErrorType.unknown)
              .having((e) => e.message, 'message', 'Groq returned no text'),
        ),
      );
    }
  });

  test('no key fails before anything is sent', () async {
    when(() => settings.cachedGroqApiKey).thenReturn(null);

    await expectLater(
      engine().transcribe(wav),
      throwsA(
        isA<CloudError>()
            .having((e) => e.type, 'type', CloudErrorType.invalidApiKey)
            .having((e) => e.service, 'service', 'Groq'),
      ),
    );
    expect(requests, isEmpty);
  });

  test('an unsupported language fails before anything is sent', () async {
    when(() => settings.groqLanguage).thenReturn('xx');

    await expectLater(
      engine().transcribe(wav),
      throwsA(
        isA<CloudError>()
            .having((e) => e.type, 'type', CloudErrorType.badRequest)
            .having(
              (e) => e.message,
              'message',
              'Unsupported language code: "xx"',
            ),
      ),
    );
    expect(requests, isEmpty);
  });

  test(
    'the free tier’s requests-per-minute limit is enforced locally',
    () async {
      final groq = engine();
      for (var i = 0; i < AppConstants.groqMaxRpm; i++) {
        await groq.transcribe(wav);
      }

      await expectLater(
        groq.transcribe(wav),
        throwsA(
          isA<CloudError>()
              .having((e) => e.type, 'type', CloudErrorType.rateLimited)
              .having((e) => e.message, 'message', 'Local rate limit reached'),
        ),
      );
      expect(requests, hasLength(AppConstants.groqMaxRpm));
    },
  );

  test('a 429 retry-after holds the next request off locally', () async {
    final groq = engine();
    reply = () => http.Response(
      '{"error":{"message":"Rate limit"}}',
      429,
      headers: {'retry-after': '30'},
    );
    await expectLater(
      groq.transcribe(wav),
      throwsA(
        isA<CloudError>().having(
          (e) => e.retryAfter,
          'retryAfter',
          const Duration(seconds: 30),
        ),
      ),
    );
    reply = () => http.Response('{"text":"later"}', 200);

    await expectLater(
      groq.transcribe(wav),
      throwsA(
        isA<CloudError>()
            .having((e) => e.type, 'type', CloudErrorType.rateLimited)
            .having(
              (e) => e.retryAfter?.inSeconds,
              'retryAfter',
              inInclusiveRange(28, 30),
            ),
      ),
    );
    expect(requests, hasLength(1));
  });

  test('other failures are rethrown without a back-off', () async {
    final groq = engine();
    reply = () => http.Response('{"error":{"message":"bad key"}}', 401);
    await expectLater(
      groq.transcribe(wav),
      throwsA(
        isA<CloudError>()
            .having((e) => e.type, 'type', CloudErrorType.invalidApiKey)
            .having((e) => e.message, 'message', 'bad key'),
      ),
    );
    reply = () => http.Response('{"text":"fine"}', 200);

    expect(await groq.transcribe(wav), 'fine');
  });
}
