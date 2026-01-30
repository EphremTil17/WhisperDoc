import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:flutter_client/services/utility/logging_service.dart';

/// Service to capture raw audio chunks.
/// Configured for 16kHz, Mono, 16-bit PCM.
class AudioService extends ChangeNotifier {
  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _recordSubscription;
  final StreamController<Uint8List> _audioStreamController =
      StreamController<Uint8List>.broadcast();

  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  Stream<double> get amplitudeStream => _amplitudeController.stream;

  Stream<Uint8List> get audioStream => _audioStreamController.stream;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  /// Lists available audio input devices (WASAPI on Windows).
  Future<List<InputDevice>> listInputDevices() async {
    return _audioRecorder.listInputDevices();
  }

  Future<void> startRecording({String? deviceId, String? deviceLabel}) async {
    if (_isRecording) return;

    if (await _audioRecorder.hasPermission()) {
      // Configuration for raw PCM (16-bit)
      // If deviceId is null, we use the library's native default path (SAFE)
      final config = deviceId != null
          ? RecordConfig(
              encoder: AudioEncoder.pcm16bits,
              sampleRate: 16000,
              numChannels: 1,
              device: InputDevice(id: deviceId, label: deviceLabel ?? ''),
            )
          : const RecordConfig(
              encoder: AudioEncoder.pcm16bits,
              sampleRate: 16000,
              numChannels: 1,
            );

      final stream = await _audioRecorder.startStream(config);
      _isRecording = true;
      notifyListeners();

      LoggingService().info('Audio recording started: 16kHz PCM 16-bit Mono');
      if (deviceLabel != null) {
        LoggingService().info('Device: $deviceLabel');
      } else {
        LoggingService().info('Device: Default');
      }

      _recordSubscription = stream.listen(
        (data) {
          _audioStreamController.add(data);
          _calculateAmplitude(data);
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

  void _calculateAmplitude(Uint8List data) {
    if (data.isEmpty) return;

    // PCM 16-bit Mono: Each sample is 2 bytes
    double total = 0;
    final int sampleCount = data.length ~/ 2;

    for (int i = 0; i < data.length - 1; i += 2) {
      // Convert 2 bytes to a 16-bit signed integer (Little Endian)
      final sample = ByteData.sublistView(
        data,
        i,
        i + 2,
      ).getInt16(0, Endian.little);
      total += sample.abs();
    }

    final average = total / sampleCount;
    // Normalize to 0.0 - 1.0 (Approximate max for 16-bit is 32767)
    final normalized = (average / 32768.0).clamp(0.0, 1.0);

    _amplitudeController.add(normalized);
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;

    await _audioRecorder.stop();
    await _recordSubscription?.cancel();
    _recordSubscription = null;

    _isRecording = false;
    _amplitudeController.add(0.0); // Reset
    notifyListeners();
  }

  @override
  Future<void> dispose() async {
    await stopRecording();
    await _audioRecorder.dispose();
    await _audioStreamController.close();
    await _amplitudeController.close();
    super.dispose();
  }
}
