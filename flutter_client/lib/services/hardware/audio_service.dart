import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:flutter_client/services/hardware/audio_input_status.dart';
import 'package:flutter_client/services/utility/logging_service.dart';

/// Service to capture raw audio chunks.
/// Configured for 16kHz, Mono, 16-bit PCM.
class AudioService extends ChangeNotifier {
  static const int _sampleRate = 16000;
  static const int _channelCount = 1;
  static const int _bytesPerSample = 2;
  static const double _pcm16NormalizationFactor = 32768.0;

  final AudioRecorder _audioRecorder;

  AudioService({AudioRecorder? audioRecorder})
    : _audioRecorder = audioRecorder ?? AudioRecorder();

  StreamSubscription<Uint8List>? _recordSubscription;
  final StreamController<Uint8List> _audioStreamController =
      StreamController<Uint8List>.broadcast();

  final StreamController<double> _amplitudeController =
      StreamController<double>.broadcast();
  bool _isRecording = false;

  AudioInputStatus _inputStatus = AudioInputStatus.unknown;

  Stream<double> get amplitudeStream => _amplitudeController.stream;
  Stream<Uint8List> get audioStream => _audioStreamController.stream;
  bool get isRecording => _isRecording;
  AudioInputStatus get inputStatus => _inputStatus;

  /// Lists available audio input devices (WASAPI on Windows).
  Future<List<InputDevice>> listInputDevices() =>
      _audioRecorder.listInputDevices();

  /// Proactively evaluates input device status and updates [inputStatus].
  Future<AudioInputStatus> evaluateInputStatus({String? targetDeviceId}) async {
    try {
      final devices = await _audioRecorder.listInputDevices();
      if (devices.isEmpty) return _setStatus(AudioInputStatus.noDevice);
      if (targetDeviceId != null &&
          !devices.any((d) => d.id == targetDeviceId)) {
        return _setStatus(AudioInputStatus.selectedUnavailable);
      }

      return _setStatus(AudioInputStatus.available);
    } catch (e, st) {
      LoggingService().error(
        'Input enumeration failed',
        error: e,
        stackTrace: st,
      );

      return _setStatus(AudioInputStatus.noDevice);
    }
  }

  AudioInputStatus _setStatus(AudioInputStatus status) {
    if (_inputStatus != status) {
      _inputStatus = status;
      notifyListeners();
    }

    return _inputStatus;
  }

  Future<void> startRecording({String? deviceId, String? deviceLabel}) async {
    if (_isRecording) return;

    if (!await _audioRecorder.hasPermission()) {
      LoggingService().error('Microphone permission denied');
      _isRecording = false;
      _setStatus(AudioInputStatus.permissionDenied);
      throw Exception('Microphone permission denied');
    }

    final config = deviceId != null
        ? RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: _sampleRate,
            numChannels: _channelCount,
            device: InputDevice(id: deviceId, label: deviceLabel ?? ''),
          )
        : const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: _sampleRate,
            numChannels: _channelCount,
          );

    try {
      final stream = await _audioRecorder.startStream(config);
      _isRecording = true;
      _setStatus(AudioInputStatus.available);
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
          // ignore: discarded_futures - stopRecording is intentionally fire-and-forget here.
          stopRecording();
        },
      );
    } catch (e) {
      _isRecording = false;
      _setStatus(AudioInputStatus.noDevice);
      notifyListeners();
      rethrow;
    }
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

  void _calculateAmplitude(Uint8List data) {
    if (data.isEmpty) return;

    // PCM 16-bit Mono: each sample is 2 bytes.
    double total = 0;
    final sampleCount = data.length ~/ _bytesPerSample;

    for (int i = 0; i < data.length - 1; i += _bytesPerSample) {
      // Convert 2 bytes to a 16-bit signed integer (little endian).
      final sample = ByteData.sublistView(
        data,
        i,
        i + _bytesPerSample,
      ).getInt16(0, Endian.little);
      total += sample.abs();
    }

    final average = total / sampleCount;
    // Normalize to 0.0 - 1.0.
    final normalized = (average / _pcm16NormalizationFactor).clamp(0.0, 1.0);
    _amplitudeController.add(normalized);
  }
}
