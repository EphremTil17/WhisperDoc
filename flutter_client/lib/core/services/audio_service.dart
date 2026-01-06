import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'logging_service.dart';

/// Service to capture raw audio chunks.
/// Configured for 16kHz, Mono, 16-bit PCM.
class AudioService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _recordSubscription;
  final StreamController<Uint8List> _audioStreamController =
      StreamController<Uint8List>.broadcast();

  Stream<Uint8List> get audioStream => _audioStreamController.stream;

  Future<void> start() async {
    if (await _audioRecorder.hasPermission()) {
      // Configuration for raw PCM (16-bit)
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      );

      final stream = await _audioRecorder.startStream(config);
      LoggingService().info('Audio recording started: 16kHz PCM 16-bit Mono');

      _recordSubscription = stream.listen(
        (data) {
          _audioStreamController.add(data);
        },
        onError: (e) {
          LoggingService().error('Audio recording error', error: e);
        },
      );
    } else {
      LoggingService().error('Microphone permission denied');
      throw Exception('Microphone permission denied');
    }
  }

  Future<void> stop() async {
    await _audioRecorder.stop();
    await _recordSubscription?.cancel();
    _recordSubscription = null;
    LoggingService().info('Audio recording stopped');
  }

  Future<void> dispose() async {
    await stop();
    await _audioRecorder.dispose();
    await _audioStreamController.close();
  }
}
