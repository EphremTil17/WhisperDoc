import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:flutter_client/services/hardware/audio_input_status.dart';
import 'package:flutter_client/services/utility/logging_service.dart';

/// Service to capture raw audio chunks.
/// Configured for 16kHz, Mono, 16-bit PCM.
class AudioService extends ChangeNotifier {
  final LoggingService _logger = LoggingService();

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
    final clock = Stopwatch()..start();
    try {
      final devices = await _audioRecorder.listInputDevices();
      final status = _classify(devices, targetDeviceId);
      _logger.debug(
        'Input check: ${status.name} (${devices.length} device(s), '
        'enumerated in ${clock.elapsedMilliseconds} ms)',
      );

      return _setStatus(status);
    } catch (e) {
      // A failed enumeration is not evidence of a missing microphone: the
      // Windows plugin fails the whole listing if any single endpoint (e.g. a
      // virtual driver or a reconnecting headset) is mid-transition. Report
      // "unknown" so recording can still be attempted; a real failure will
      // surface from startRecording, and the next device event re-checks.
      _logger.warning('Input enumeration failed; availability unknown: $e');

      return _setStatus(AudioInputStatus.unknown);
    }
  }

  static AudioInputStatus _classify(
    List<InputDevice> devices,
    String? targetDeviceId,
  ) {
    if (devices.isEmpty) return AudioInputStatus.noDevice;
    if (targetDeviceId != null && !devices.any((d) => d.id == targetDeviceId)) {
      return AudioInputStatus.selectedUnavailable;
    }

    return AudioInputStatus.available;
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
      _logger.error('Microphone permission denied');
      _isRecording = false;
      _setStatus(AudioInputStatus.permissionDenied);
      throw Exception('Microphone permission denied');
    }

    final config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _sampleRate,
      numChannels: _channelCount,
      device: deviceId != null
          ? InputDevice(id: deviceId, label: deviceLabel ?? '')
          : null,
      // If the device disappears mid-recording, continue on the system default
      // (the same selected-to-default fallback used when starting). record 7
      // otherwise pauses, which would silently stall the dictation.
      audioRouteChange: AudioRouteChangeMode.follow,
    );

    try {
      final stream = await _audioRecorder.startStream(config);
      _isRecording = true;
      _setStatus(AudioInputStatus.available);
      notifyListeners();

      _logger.info('Audio recording started: 16kHz PCM 16-bit Mono');
      if (deviceLabel != null) {
        _logger.info('Device: $deviceLabel');
      } else {
        _logger.info('Device: Default');
      }

      _recordSubscription = stream.listen(
        (data) {
          _audioStreamController.add(data);
          _calculateAmplitude(data);
        },
        onError: (e) {
          _logger.error('Audio recording error', error: e);
          // ignore: discarded_futures - stopRecording is intentionally fire-and-forget here.
          stopRecording();
        },
      );
    } catch (e) {
      _isRecording = false;
      // Derive status from the actual device list rather than assuming the
      // microphone is gone: a busy or transient device must stay retryable.
      await evaluateInputStatus(targetDeviceId: deviceId);
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

    // PCM 16-bit Mono: each sample is 2 bytes. One view per chunk; this runs
    // for every captured chunk (~16k samples/s).
    double total = 0;
    final sampleCount = data.length ~/ _bytesPerSample;
    final samples = ByteData.sublistView(data);

    for (int i = 0; i < data.length - 1; i += _bytesPerSample) {
      total += samples.getInt16(i, Endian.little).abs();
    }

    final average = total / sampleCount;
    // Normalize to 0.0 - 1.0.
    final normalized = (average / _pcm16NormalizationFactor).clamp(0.0, 1.0);
    _amplitudeController.add(normalized);
  }
}
