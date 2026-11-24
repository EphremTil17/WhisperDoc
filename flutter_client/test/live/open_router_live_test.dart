// Live checks against OpenRouter itself; they spend a fraction of a cent.
// Skipped unless OPENROUTER_API_KEY is set, so CI never runs them. Before a
// release, from PowerShell:
//   $env:OPENROUTER_API_KEY = '<key>'; flutter test test/live
// ignore_for_file: prefer-match-file-name, avoid-late-keyword
@Tags(['live'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/transcription/cloud_error.dart';
import 'package:flutter_client/services/transcription/cloud_http.dart';
import 'package:flutter_client/services/transcription/open_router_catalog.dart';
import 'package:flutter_client/services/transcription/open_router_chat_engine.dart';
import 'package:flutter_client/services/transcription/open_router_speech_engine.dart';
import 'package:flutter_client/services/transcription/wav_encoder.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSettings extends Mock
    with ChangeNotifier
    implements SettingsService {}

void main() {
  final key = Platform.environment['OPENROUTER_API_KEY'];
  final skip = key == null ? 'OPENROUTER_API_KEY is not set' : null;
  const whisperTurbo = 'openai/whisper-large-v3-turbo';
  const samplesPerSecond = AppConstants.pcmBytesPerSecond ~/ 2;
  const toneHertz = 440.0;
  const toneAmplitude = 300.0;
  const fullTurn = math.pi * 2;
  const rewriteTokens = 64;
  const rewriteTimeout = Duration(seconds: 20);

  late CloudHttp http;
  late _MockSettings settings;
  late OpenRouterCatalog catalog;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    http = CloudHttp();
    settings = _MockSettings();
    when(() => settings.cachedOpenRouterApiKey).thenReturn(key);
    when(() => settings.transcriptionSource)
        .thenReturn(TranscriptionSource.openRouter);
    when(() => settings.openRouterZdr).thenReturn(true);
    when(() => settings.openRouterModel).thenReturn(whisperTurbo);
    when(() => settings.openRouterLanguage).thenReturn('en');
    when(() => settings.openRouterRewriteModel)
        .thenReturn(AppConstants.openRouterTransformModel);
    catalog = OpenRouterCatalog(settings, http);
    addTearDown(catalog.dispose);
    addTearDown(http.dispose);
  });

  /// One second of a quiet tone: no words, but a valid clip end to end.
  Uint8List toneWav() {
    final pcm = Int16List.fromList([
      for (var i = 0; i < samplesPerSecond; i++)
        (math.sin(fullTurn * toneHertz * i / samplesPerSecond) * toneAmplitude)
            .round(),
    ]);

    return WavEncoder.encode(pcm.buffer.asUint8List());
  }

  test('the live list has zero-retention speech models', () async {
    await catalog.refresh();

    expect(catalog.lastError, isNull);
    final choices = catalog.choices;
    expect(choices, isNotEmpty);
    expect(choices.every((m) => m.zdr), isTrue);
    expect(catalog.find(whisperTurbo), isNotNull);
  }, skip: skip);

  test('OpenRouter reports a latency for the models it serves', () async {
    await catalog.refresh();

    await catalog.loadLatency();

    final figures = [
      for (final model in catalog.choices) ?catalog.latencyOf(model.id),
    ];
    expect(figures, isNotEmpty);
  }, skip: skip);

  test(
    'zero data retention is enforced by OpenRouter, not just asked',
    () async {
      // Grok STT keeps data (30 days) and has no zero-retention host, so a
      // request that insists on one must be refused rather than served.
      when(() => settings.openRouterModel).thenReturn('x-ai/grok-stt-2.0');
      final engine = OpenRouterSpeechEngine(settings, http, catalog);

      await expectLater(
        engine.transcribe(toneWav()),
        throwsA(
          isA<CloudError>().having(
            (e) => e.type,
            'type',
            CloudErrorType.modelUnavailable,
          ),
        ),
      );
      await catalog.refresh();
    },
    skip: skip,
  );

  test('a clip goes up as JSON and comes back as text', () async {
    final engine = OpenRouterSpeechEngine(settings, http, catalog);

    final text = await engine.transcribe(toneWav());

    expect(text, isA<String>());
  }, skip: skip);

  test('a retired model id is reported as retired', () async {
    when(() => settings.openRouterModel).thenReturn('acme/not-a-model');
    final engine = OpenRouterSpeechEngine(settings, http, catalog);

    await expectLater(
      engine.transcribe(toneWav()),
      throwsA(
        isA<CloudError>().having(
          (e) => e.type,
          'type',
          CloudErrorType.modelRetired,
        ),
      ),
    );
    // The forced refresh it set off is in flight; let it land.
    await catalog.refresh();
    expect(catalog.lastError, isNull);
  }, skip: skip);

  test('an output style rewrites through OpenRouter', () async {
    final engine = OpenRouterChatEngine(settings, http);

    final result = await engine.complete(
      systemPrompt:
          'Rewrite the transcript inside <transcript> tags as one clean '
          'sentence. Output only the sentence.',
      userContent: '<transcript>\num so the build passed\n</transcript>',
      maxTokens: rewriteTokens,
      timeout: rewriteTimeout,
    );

    expect(result.text.toLowerCase(), contains('build'));
    expect(result.finishReason, isNot('length'));
  }, skip: skip);

  test('a rewrite model is checked the way the styles would use it', () async {
    final engine = OpenRouterChatEngine(settings, http);

    final verdicts = [
      for (final model in [
        AppConstants.openRouterTransformModel,
        // Can't turn reasoning off.
        'openai/gpt-oss-20b',
        'acme/no-such-model',
      ])
        await engine.checkModel(model),
    ];

    expect(verdicts, [
      isNull,
      'This model always reasons first, which is too slow for styles.',
      'OpenRouter has no model by this id.',
    ]);
  }, skip: skip);
}
