import 'package:flutter/foundation.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:flutter_client/logic/processors/text_sanitizer.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';

import 'cloud_error.dart';
import 'speech_engine.dart';
import 'wav_encoder.dart';

/// A cloud dictation from start to text: the audio is held in memory while
/// the user talks and uploaded to the active cloud source when they stop.
/// The WebSocket path to the user's own server never comes through here.
class CloudTranscriptionService {
  CloudTranscriptionService(this._settings, List<SpeechEngine> engines)
    : _engines = {for (final engine in engines) engine.source: engine};

  final SettingsService _settings;
  final Map<TranscriptionSource, SpeechEngine> _engines;

  final List<Uint8List> _chunks = [];
  int _totalBytes = 0;

  /// The active source's engine; null when the server is the source.
  SpeechEngine? get _engine => _engines[_settings.transcriptionSource];

  /// Why the active cloud source can't take a dictation yet; null when it
  /// can. See [SpeechEngine.setupProblem].
  String? get setupProblem => _engine?.setupProblem;

  /// The longest recording one upload to the active source can carry.
  Duration get maxClipDuration => Duration(
    seconds: (_engine?.maxClipBytes ?? 0) ~/ AppConstants.pcmBytesPerSecond,
  );

  @visibleForTesting
  int get bufferSizeBytes => _totalBytes;

  /// Starts a dictation: drops any leftover audio and warms the connection
  /// the upload will use.
  void begin() {
    clearBuffer();
    _engine?.warmUp();
  }

  /// Keeps a chunk of PCM. Returns false once the clip would exceed what one
  /// upload can carry; the caller then stops recording and transcribes what
  /// it has, and later chunks are refused too.
  bool bufferAudioChunk(Uint8List data) {
    final limit = _engine?.maxClipBytes ?? 0;
    if (_totalBytes + data.length > limit) {
      LoggingService().warning(
        'Cloud buffer reached its $limit-byte ceiling; stopping recording',
      );

      return false;
    }
    _chunks.add(data);
    _totalBytes += data.length;

    return true;
  }

  /// Uploads the buffered clip and returns its sanitized text. The audio is
  /// released whatever happens: nothing retries a clip. Throws `CloudError`.
  Future<String> finalizeAndTranscribe() async {
    final engine = _engine;
    if (engine == null) {
      throw StateError('No cloud source is active');
    }
    if (_totalBytes == 0) {
      throw CloudError(
        service: engine.source.label,
        type: CloudErrorType.noAudio,
        message: 'No audio was recorded',
      );
    }
    final wav = WavEncoder.encodeChunks(_chunks, _totalBytes);
    clearBuffer();

    // Cloud output bypasses the server's sanitizer: strip ANSI escapes and
    // control characters before the text can reach the clipboard or a paste.
    return TextSanitizer.sanitize(await engine.transcribe(wav));
  }

  /// Discards buffered audio without transcribing.
  void clearBuffer() {
    _chunks.clear();
    _totalBytes = 0;
  }
}
