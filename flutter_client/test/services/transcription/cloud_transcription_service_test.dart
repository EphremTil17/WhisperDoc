// Byte sizes are the subject under test; fakes are rebuilt per test.
// ignore_for_file: no-magic-number, avoid-late-keyword, prefer-match-file-name
import 'dart:typed_data';

import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/services/transcription/cloud_error.dart';
import 'package:flutter_client/services/transcription/cloud_transcription_service.dart';
import 'package:flutter_client/services/transcription/speech_engine.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSettingsService extends Mock implements SettingsService {}

/// Records what it is sent and answers with [reply].
class _FakeEngine implements SpeechEngine {
  _FakeEngine(this.source, {this.maxClipBytes = 10});

  @override
  final TranscriptionSource source;

  @override
  final int maxClipBytes;

  @override
  String? setupProblem;

  int warmUps = 0;
  final List<Uint8List> sent = [];
  Future<String> Function() reply = () async => 'hello';

  @override
  void warmUp() => warmUps++;

  @override
  Future<String> transcribe(Uint8List wav) {
    sent.add(wav);

    return reply();
  }
}

void main() {
  late _MockSettingsService settings;
  late _FakeEngine groq;
  late _FakeEngine openRouter;
  late CloudTranscriptionService service;

  void use(TranscriptionSource source) =>
      when(() => settings.transcriptionSource).thenReturn(source);

  Uint8List bytes(List<int> values) => Uint8List.fromList(values);

  setUp(() {
    settings = _MockSettingsService();
    groq = _FakeEngine(TranscriptionSource.groq, maxClipBytes: 6);
    openRouter = _FakeEngine(
      TranscriptionSource.openRouter,
      maxClipBytes: 64000,
    );
    service = CloudTranscriptionService(settings, [groq, openRouter]);
    use(TranscriptionSource.groq);
  });

  test('the setup problem is the active source’s', () {
    groq.setupProblem = 'Add your Groq API key in Account.';
    expect(service.setupProblem, 'Add your Groq API key in Account.');

    use(TranscriptionSource.openRouter);
    expect(service.setupProblem, isNull);
  });

  test('the server source has no cloud credentials or clip limit', () {
    use(TranscriptionSource.server);

    expect(service.setupProblem, isNull);
    expect(service.maxClipDuration, Duration.zero);
  });

  test('the longest clip is the active engine’s limit', () {
    use(TranscriptionSource.openRouter);

    expect(service.maxClipDuration, const Duration(seconds: 2));
  });

  test('the real limits allow minutes of audio per source', () {
    expect(
      AppConstants.groqMaxBufferBytes ~/ AppConstants.pcmBytesPerSecond,
      greaterThan(12 * 60),
    );
    expect(
      AppConstants.openRouterMaxBufferBytes ~/ AppConstants.pcmBytesPerSecond,
      inInclusiveRange(9 * 60, 10 * 60),
    );
  });

  test('begin() drops leftover audio and warms only the active source', () {
    service.bufferAudioChunk(bytes([1, 2]));

    service.begin();

    expect(service.bufferSizeBytes, 0);
    expect(groq.warmUps, 1);
    expect(openRouter.warmUps, 0);
  });

  test('begin() for the server warms nothing', () {
    use(TranscriptionSource.server);

    service.begin();

    expect(groq.warmUps + openRouter.warmUps, 0);
  });

  test('takes chunks up to the active source’s ceiling and no more', () {
    expect(service.bufferAudioChunk(bytes([1, 2, 3, 4])), isTrue);
    expect(service.bufferAudioChunk(bytes([5, 6])), isTrue);
    final full = service.bufferSizeBytes;

    expect(service.bufferAudioChunk(bytes([7])), isFalse);
    expect(full, 6);
    expect(service.bufferSizeBytes, full);
  });

  test('the server source buffers nothing', () {
    use(TranscriptionSource.server);

    expect(service.bufferAudioChunk(bytes([1])), isFalse);
  });

  test('uploads one WAV of every chunk, then empties the buffer', () async {
    service
      ..bufferAudioChunk(bytes([1, 2]))
      ..bufferAudioChunk(bytes([3, 4, 5]));

    final text = await service.finalizeAndTranscribe();

    final wav = groq.sent.single;
    expect(text, 'hello');
    expect(wav.length, 44 + 5);
    expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
    expect(wav.sublist(44), [1, 2, 3, 4, 5]);
    expect(service.bufferSizeBytes, 0);
    expect(openRouter.sent, isEmpty);
  });

  test('cloud text is sanitized before it can be pasted', () async {
    groq.reply = () async => 'ok\u001B[31m red\u0007';
    service.bufferAudioChunk(bytes([1]));

    expect(await service.finalizeAndTranscribe(), 'ok red');
  });

  test('a failed upload still releases the audio', () async {
    groq.reply = () async => throw const CloudError(
      service: 'Groq',
      type: CloudErrorType.serverError,
      message: 'down',
    );
    service.bufferAudioChunk(bytes([1, 2]));

    await expectLater(
      service.finalizeAndTranscribe(),
      throwsA(isA<CloudError>()),
    );
    expect(service.bufferSizeBytes, 0);
  });

  test('an empty recording costs no request', () async {
    await expectLater(
      service.finalizeAndTranscribe(),
      throwsA(
        isA<CloudError>()
            .having((e) => e.type, 'type', CloudErrorType.noAudio)
            .having((e) => e.service, 'service', 'Groq')
            .having((e) => e.message, 'message', 'No audio was recorded'),
      ),
    );
    expect(groq.sent, isEmpty);
  });

  test('transcribing with the server as source is a programming error', () {
    use(TranscriptionSource.server);

    expect(service.finalizeAndTranscribe, throwsStateError);
  });

  test('clearBuffer discards audio without uploading', () {
    service
      ..bufferAudioChunk(bytes([1, 2, 3]))
      ..clearBuffer();

    expect(service.bufferSizeBytes, 0);
    expect(groq.sent, isEmpty);
  });
}
