import 'dart:typed_data';

import 'package:flutter_client/logic/models/transcription_source.dart';

/// A cloud speech-to-text service a finished recording is uploaded to.
abstract interface class SpeechEngine {
  TranscriptionSource get source;

  /// Why a dictation can't start with this service yet (no key, no usable
  /// model), as the message to show; null when it is ready. Checked before
  /// the microphone opens, so a doomed recording never starts.
  String? get setupProblem;

  /// The largest clip, in raw PCM bytes, one request can carry.
  int get maxClipBytes;

  /// Opens the connection while the user is still talking, so the upload
  /// does not wait on a TLS handshake when they stop.
  void warmUp();

  /// Transcribes a WAV clip. Throws `CloudError`.
  Future<String> transcribe(Uint8List wav);
}
