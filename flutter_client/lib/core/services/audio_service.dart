import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'logging_service.dart';

/// Service to capture raw audio chunks.
/// Configured for 16kHz, Mono, 16-bit PCM.
class AudioService extends ChangeNotifier {
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _recordSubscription;
  final StreamController<Uint8List> _audioStreamController =
      StreamController<Uint8List>.broadcast();

  Stream<Uint8List> get audioStream => _audioStreamController.stream;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  Future<void> startRecording() async {
    if (_isRecording) return;

    if (await _audioRecorder.hasPermission()) {
      // Configuration for raw PCM (16-bit)
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      );

      final stream = await _audioRecorder.startStream(config);
      _isRecording = true;
      notifyListeners();

      LoggingService().info('Audio recording started: 16kHz PCM 16-bit Mono');

      _recordSubscription = stream.listen(
        (data) {
          _audioStreamController.add(data);
        },
        onError: (e) {
          LoggingService().error('Audio recording error', error: e);
          // ignore: discarded_futures
          stopRecording();
        },
      );
    } else {
      LoggingService().error('Microphone permission denied');
      _isRecording = false;
      notifyListeners();
      throw Exception('Microphone permission denied');
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;

    await _audioRecorder.stop();
    await _recordSubscription?.cancel();
    _recordSubscription = null;

    _isRecording = false;
    notifyListeners();

    LoggingService().info('Audio recording stopped');
  }

  // Aliases for compatibility if needed, or remove if direct calls used
  Future<void> start() => startRecording();
  Future<void> stop() => stopRecording();

  @override
  Future<void> dispose() async {
    await stopRecording();
    await _audioRecorder.dispose();
    await _audioStreamController.close();
    super.dispose();
  }
}
