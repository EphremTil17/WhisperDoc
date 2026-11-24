// Status codes and byte sizes are the subject under test; mocks are rebuilt
// per test and the same engine call is repeated on purpose.
// ignore_for_file: no-magic-number, avoid-late-keyword, prefer-match-file-name, prefer-moving-to-variable
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/transcription/cloud_error.dart';
import 'package:flutter_client/services/transcription/cloud_http.dart';
import 'package:flutter_client/logic/models/model_selection_problem.dart';
import 'package:flutter_client/services/transcription/open_router_catalog.dart';
import 'package:flutter_client/services/transcription/open_router_speech_engine.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

class _MockSettingsService extends Mock implements SettingsService {}

class _MockCatalog extends Mock
    with ChangeNotifier
    implements OpenRouterCatalog {}

void main() {
  final wav = Uint8List.fromList([82, 73, 70, 70, 0, 255]);
  late _MockSettingsService settings;
  late _MockCatalog catalog;
  late List<http.Request> requests;
  late http.Response Function() reply;

  OpenRouterSpeechEngine engine() => OpenRouterSpeechEngine(
    settings,
    CloudHttp(
      client: MockClient((request) async {
        requests.add(request);

        return reply();
      }),
    ),
    catalog,
  );

  Map<String, dynamic> sentBody() =>
      jsonDecode(requests.single.body) as Map<String, dynamic>;

  setUp(() {
    settings = _MockSettingsService();
    catalog = _MockCatalog();
    when(() => settings.cachedOpenRouterApiKey).thenReturn('sk-or-test');
    when(() => settings.openRouterModel)
        .thenReturn('microsoft/mai-transcribe-2');
    when(() => settings.openRouterLanguage).thenReturn('');
    when(() => settings.openRouterZdr).thenReturn(true);
    when(() => catalog.refresh(force: any(named: 'force')))
        .thenAnswer((_) => Future.value());
    when(() => catalog.selectionProblem).thenReturn(ModelSelectionProblem.none);
    requests = [];
    reply = () => http.Response(
      '{"text":"Send it.","usage":{"seconds":3.4,"cost":0.0001}}',
      200,
    );
  });

  test('describes itself as OpenRouter with its upload limit', () {
    final openRouter = engine();

    expect(openRouter.source, TranscriptionSource.openRouter);
    expect(openRouter.maxClipBytes, AppConstants.openRouterMaxBufferBytes);
    expect(openRouter.setupProblem, isNull);
    for (final key in ['', null]) {
      when(() => settings.cachedOpenRouterApiKey).thenReturn(key);
      expect(
        openRouter.setupProblem,
        'Add your OpenRouter API key in Account.',
        reason: '$key',
      );
    }
  });

  test('won’t start with a model the catalog knows can’t be used', () {
    const expected = {
      ModelSelectionProblem.none: null,
      ModelSelectionProblem.notChosen: 'Choose an OpenRouter model in Account.',
      ModelSelectionProblem.retired:
          'OpenRouter stopped serving your model. Choose another in Account.',
      ModelSelectionProblem.retainsData:
          'Zero data retention is on, and your model keeps data. '
          'Choose another in Account.',
    };
    final actual = <ModelSelectionProblem, String?>{};
    for (final problem in expected.keys) {
      when(() => catalog.selectionProblem).thenReturn(problem);
      actual[problem] = engine().setupProblem;
    }

    expect(actual, expected);
  });

  test('warms the connection to OpenRouter’s origin', () async {
    engine().warmUp();
    await pumpEventQueue();

    expect(requests.single.method, 'HEAD');
    expect(requests.single.url, Uri.parse(AppConstants.openRouterOrigin));
  });

  test('posts JSON with base64 audio and zero data retention', () async {
    final text = await engine().transcribe(wav);

    final request = requests.single;
    expect(text, 'Send it.');
    expect(
      request.url,
      Uri.parse(AppConstants.openRouterTranscriptionEndpoint),
    );
    expect(request.headers['Authorization'], 'Bearer sk-or-test');
    expect(sentBody(), {
      'model': 'microsoft/mai-transcribe-2',
      'temperature': 0,
      'provider': {'zdr': true},
      'input_audio': {'format': 'wav', 'data': base64Encode(wav)},
    });
  });

  test('names the language, and asks for no ZDR once it is off', () async {
    when(() => settings.openRouterLanguage).thenReturn('fr');
    when(() => settings.openRouterZdr).thenReturn(false);

    await engine().transcribe(wav);

    final body = sentBody();
    expect(body['language'], 'fr');
    expect(body['provider'], isEmpty);
  });

  test('a long clip is encoded off the UI thread, byte for byte', () async {
    final long = Uint8List.fromList(
      List.generate(1024 * 1024 + 1, (i) => i % 251),
    );

    await engine().transcribe(long);

    final audio = sentBody()['input_audio'] as Map<String, dynamic>;
    expect(base64Decode(audio['data'] as String), long);
  });

  test('encodeRequest adds the clip as raw base64 to the fields', () {
    final json = jsonDecode(
      utf8.decode(OpenRouterSpeechEngine.encodeRequest({'model': 'a/b'}, wav)),
    );

    expect(json, {
      'model': 'a/b',
      'input_audio': {'format': 'wav', 'data': 'UklGRgD/'},
    });
  });

  test('providerPreferences asks for ZDR only when it is on', () {
    expect(OpenRouterSpeechEngine.providerPreferences(zdr: true), {
      'zdr': true,
    });
    expect(OpenRouterSpeechEngine.providerPreferences(zdr: false), isEmpty);
  });

  test('no key or no model fails before anything is sent', () async {
    when(() => settings.cachedOpenRouterApiKey).thenReturn(null);
    await expectLater(
      engine().transcribe(wav),
      throwsA(
        isA<CloudError>()
            .having((e) => e.type, 'type', CloudErrorType.invalidApiKey)
            .having((e) => e.service, 'service', 'OpenRouter'),
      ),
    );

    when(() => settings.cachedOpenRouterApiKey).thenReturn('sk-or-test');
    when(() => settings.openRouterModel).thenReturn(null);
    await expectLater(
      engine().transcribe(wav),
      throwsA(
        isA<CloudError>()
            .having((e) => e.type, 'type', CloudErrorType.modelUnavailable)
            .having((e) => e.message, 'message', 'No OpenRouter model chosen'),
      ),
    );
    expect(requests, isEmpty);
  });

  test('an unavailable model asks the catalog for a fresh list', () async {
    reply = () => http.Response(
      '{"error":{"message":"No endpoints found matching your data policy"}}',
      404,
    );

    await expectLater(
      engine().transcribe(wav),
      throwsA(
        isA<CloudError>().having(
          (e) => e.type,
          'type',
          CloudErrorType.modelUnavailable,
        ),
      ),
    );
    verify(() => catalog.refresh(force: true)).called(1);
  });

  test('a retired model asks the catalog for a fresh list too', () async {
    reply = () => http.Response(
      '{"error":{"message":"Model acme/gone does not exist","code":400}}',
      400,
    );

    await expectLater(
      engine().transcribe(wav),
      throwsA(
        isA<CloudError>().having(
          (e) => e.type,
          'type',
          CloudErrorType.modelRetired,
        ),
      ),
    );
    verify(() => catalog.refresh(force: true)).called(1);
  });

  test('other failures leave the catalog alone', () async {
    reply = () => http.Response('{"error":{"message":"no credits"}}', 402);

    await expectLater(
      engine().transcribe(wav),
      throwsA(
        isA<CloudError>().having(
          (e) => e.type,
          'type',
          CloudErrorType.insufficientCredits,
        ),
      ),
    );
    verifyNever(() => catalog.refresh(force: any(named: 'force')));
  });

  test('a reply without text is an unknown error', () async {
    reply = () => http.Response('{"usage":{}}', 200);

    await expectLater(
      engine().transcribe(wav),
      throwsA(
        isA<CloudError>()
            .having((e) => e.type, 'type', CloudErrorType.unknown)
            .having((e) => e.message, 'message', 'OpenRouter returned no text'),
      ),
    );
  });
}
