// Each notifyListeners() announces a different state change and returns
// nothing, so the repeats have no value to share.
// ignore_for_file: prefer-moving-to-variable
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_client/logic/models/history_entry.dart';
import 'package:flutter_client/services/hardware/audio_device_monitor.dart';
import 'package:flutter_client/services/hardware/audio_input_status.dart';
import 'package:flutter_client/services/hardware/audio_service.dart';
import 'package:flutter_client/services/utility/automation_service.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/hardware/audio_cue_service.dart';
import 'package:flutter_client/services/utility/history_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/transcription/groq_transcription_service.dart';
import 'package:flutter_client/services/transcription/groq_transform_service.dart';
import 'package:flutter_client/services/transcription/groq_error.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/processors/audio_signal_processor.dart';

/// Controller managing recording state, transcription, and automation.
///
/// Orchestrates audio capture, WebSocket communication, and post-processing.
class RecordingController extends ChangeNotifier {
  final LoggingService _logger = LoggingService();

  final AudioService _audioService;
  final WebSocketService _wsService;
  final GroqTranscriptionService _groqService;
  final GroqTransformService _transformService;
  final AutomationService _automationService;
  final HistoryService _historyService;
  final SettingsService _settingsService;
  final AudioCueService _audioCueService;
  final AudioSignalProcessor _signalProcessor = AudioSignalProcessor();

  StreamSubscription? _audioSubscription;
  StreamSubscription? _messageSubscription;
  StreamSubscription<void>? _deviceChangeSubscription;

  // Buffer of transcription segments (limited to prevent memory issues)
  final List<HistoryEntry> _history = [];
  int _historyRevision = 0;

  /// Runs from the stop until the paste, for the timing log line.
  final Stopwatch _sinceStop = Stopwatch();

  // Current active transcription buffer (accumulating text)
  String _currentBuffer = '';
  DateTime? _transcriptAt;

  // Single source of truth for recording state
  bool _isRecording = false;

  // Liveness check - warning if no audio signal is detected
  bool _showSilenceWarning = false;

  // Groq transcription lockout — single source of truth for all UI/hotkey paths
  bool _isTranscribing = false;

  // Re-entry guards for overlapping start/stop requests (rapid hotkey presses).
  bool _isStarting = false;
  bool _stopRequested = false;
  bool _isStopping = false;
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  // Getters
  bool get showSilenceWarning => _showSilenceWarning;
  bool get isTranscribing => _isTranscribing;
  bool get incognitoMode => _settingsService.incognitoMode;
  String get currentText => _currentBuffer;

  /// When [currentText] was produced; null while there is none.
  DateTime? get transcriptAt => _transcriptAt;
  bool get isRecording => _isRecording;

  /// True while recording or while a Groq transcription/transform is in flight.
  bool get isSessionActive => _isRecording || _isTranscribing;
  AudioInputStatus get inputStatus => _audioService.inputStatus;
  List<HistoryEntry> get history => List.unmodifiable(_history);

  /// Bumped whenever [history] changes. [history] returns a fresh list on
  /// every read, so widgets select this to rebuild only when it moved.
  int get historyRevision => _historyRevision;
  Stream<String> get onError => _errorController.stream;

  RecordingController({
    required this._audioService,
    required this._wsService,
    required this._groqService,
    required this._transformService,
    required this._automationService,
    required this._historyService,
    required this._settingsService,
    required this._audioCueService,
    required AudioDeviceMonitor deviceMonitor,
  }) {
    _initListeners();
    // Listen to AudioService state changes
    _audioService.addListener(_onAudioStateChanged);
    // Sync with settings changes and re-verify hardware
    _settingsService.addListener(_onSettingsChanged);
    // Re-verify hardware the moment the OS reports a device plug/unplug.
    _deviceChangeSubscription = deviceMonitor.changes.listen(
      (_) => unawaited(refreshHardwareStatus()),
    );
    // Load initial history from encrypted storage and check initial hardware status
    unawaited(_loadHistory());
    unawaited(refreshHardwareStatus());
  }

  /// Helper to get decrypted text for an entry (used by UI)
  String getDecryptedText(HistoryEntry entry) {
    return _historyService.decryptEntry(entry);
  }

  /// Enables incognito mode and clears existing history
  Future<void> enableIncognitoMode() async {
    await _settingsService.setIncognitoMode(true);
    await _clearSensitiveData();
    _logger.info(
      'Incognito mode enabled - history and buffers cleared',
    );
  }

  /// Disables incognito mode (history recording resumes)
  Future<void> disableIncognitoMode() async {
    await _settingsService.setIncognitoMode(false);
    unawaited(_loadHistory());
    _logger.info('Incognito mode disabled - history restored');
  }

  /// Clears all transcription history
  Future<void> clearHistory() async {
    await _historyService.clearAll();
    await _loadHistory();
  }

  Future<void> toggleRecording() async {
    if (_isRecording) {
      await stopRecording();
    } else if (_isStarting) {
      // A second press while the microphone is still opening means
      // "never mind": honour it once the start has finished.
      _stopRequested = true;
    } else {
      await startRecording();
    }
  }

  Future<void> startRecording() async {
    // Groq transcription lockout — prevent hotkey/capsule race during upload.
    // A start already in flight must not open a second capture stream.
    if (_isTranscribing || _isStarting) return;
    _isStarting = true;
    _stopRequested = false;
    try {
      await _beginRecording();
    } finally {
      _isStarting = false;
    }
    if (_stopRequested) {
      _stopRequested = false;
      await stopRecording();
    }
  }

  Future<void> _beginRecording() async {
    // Hardware input guard — prevent recording start when hardware is unavailable.
    // A degraded status may be stale (e.g. set before a device was connected),
    // so re-check once before refusing; one enumeration costs a few ms.
    var inputStatus = _audioService.inputStatus;
    if (!inputStatus.canRecord) {
      inputStatus = await refreshHardwareStatus();
    }
    if (!inputStatus.canRecord) {
      _errorController.add(
        inputStatus.bannerMessage ??
            'Recording blocked: No microphone connected.',
      );

      return;
    }

    _setTranscript('');
    _showSilenceWarning = false;
    notifyListeners();

    final isGroqMode = _settingsService.isGroqMode;

    try {
      // 1. Mode-aware credential check.
      if (isGroqMode) {
        if (!_groqService.hasValidCredentials) {
          _errorController.add(
            'Please configure your Groq API key in Settings.',
          );

          return;
        }
      } else {
        if (!_wsService.hasValidCredentials) {
          _errorController.add('Please authenticate in Settings first.');

          return;
        }
      }

      // 2. ZERO-LATENCY START: Initiate capture and cues instantly.
      // A missing saved microphone falls back to the system default device.
      final useDefault = inputStatus.usesDefaultDevice;
      final String? deviceId = useDefault
          ? null
          : _settingsService.microphoneId;
      final String? deviceLabel = useDefault
          ? null
          : _settingsService.microphoneLabel;

      await _audioService.startRecording(
        deviceId: deviceId,
        deviceLabel: deviceLabel,
      );
      _audioCueService.playStartCue();

      notifyListeners();

      // 3. Mode-aware audio piping, on a fresh subscription: a stale one
      // would deliver every chunk twice.
      await _audioSubscription?.cancel();
      if (isGroqMode) {
        _groqService.clearBuffer();
        _audioSubscription = _audioService.audioStream.listen((data) {
          final accepted = _groqService.bufferAudioChunk(data);
          if (!accepted && _isRecording) {
            // Buffer ceiling reached — stop recording and transcribe the
            // buffered prefix so the user gets a result, not silent truncation.
            _errorController.add(
              'Max clip length reached (~${AppConstants.groqMaxRecordingDuration.inMinutes} min). '
              'Transcribing captured audio.',
            );
            unawaited(stopRecording());
          }
        });
      } else {
        _audioSubscription = _audioService.audioStream.listen((data) {
          _wsService.sendAudioChunk(data);
        });

        // 5. TRANSPORT AUTONOMY: Ensure server is awake in parallel.
        unawaited(() async {
          final connected = await _wsService.ensureConnected();
          if (!connected && _isRecording) {
            unawaited(stopRecording());
            _errorController.add('Failed to wake up server connection.');
          }
        }());
      }

      // 4. Liveness Probe (Reactive Silence Detection) — both modes.
      unawaited(() async {
        final isSilent = await _signalProcessor.detectSilence(
          _audioService.amplitudeStream,
        );
        if (isSilent && _isRecording) {
          _showSilenceWarning = true;
          notifyListeners();
          _logger.warning(
            'No audio detected after 3 seconds. Virtual driver conflict suspected.',
          );
        }
      }());
    } catch (e, st) {
      _logger.error(
        'Failed to start recording',
        error: e,
        stackTrace: st,
      );
      // AudioService owns hardware truth: if the failure was hardware-related
      // it has already set a degraded status. Anything else stays a generic,
      // retryable error and must NOT disable the microphone.
      _errorController.add(
        _audioService.inputStatus.bannerMessage ??
            'Could not start recording. Please try again.',
      );
      _isRecording = false;
      notifyListeners();
    }
  }

  Future<void> stopRecording() async {
    // Claim the stop synchronously: the buffer-cap path (once per late chunk)
    // and the hotkey can request it while the recorder is still shutting
    // down, and each extra pass would upload and paste the clip again.
    if (_isStopping || !_audioService.isRecording) return;
    _isStopping = true;
    _sinceStop
      ..reset()
      ..start();
    try {
      await _audioService.stopRecording();
      await _finishCapture();
    } finally {
      _isStopping = false;
    }
  }

  /// Ends a capture the same way whoever stopped it: the user, or the
  /// recorder itself (a device error): cue, drop the stream, and transcribe
  /// what was recorded.
  Future<void> _finishCapture() async {
    _audioCueService.playStopCue();
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    if (_settingsService.isGroqMode) {
      unawaited(_transcribeWithGroq());
    } else {
      _wsService.sendEndSignal();
    }
  }

  @override
  void dispose() {
    // Memory only: disposing the controller must never delete the history
    // on disk (that is what incognito asks for, not shutdown).
    _setTranscript('');
    _history.clear();
    _audioService.removeListener(_onAudioStateChanged);
    _settingsService.removeListener(_onSettingsChanged);
    unawaited(_audioSubscription?.cancel());
    unawaited(_messageSubscription?.cancel());
    unawaited(_deviceChangeSubscription?.cancel());
    unawaited(_errorController.close());
    super.dispose();
  }

  void _initListeners() {
    _messageSubscription = _wsService.onMessage.listen(_handleWebSocketMessage);
  }

  void _onSettingsChanged() {
    notifyListeners();
    unawaited(refreshHardwareStatus());
  }

  /// Public pass-through method to trigger hardware status re-evaluation.
  Future<AudioInputStatus> refreshHardwareStatus() => _audioService
      .evaluateInputStatus(targetDeviceId: _settingsService.microphoneId);

  void _onAudioStateChanged() {
    final wasRecording = _isRecording;
    _isRecording = _audioService.isRecording;
    if (wasRecording && !_isRecording && !_isStopping) {
      // The recorder stopped on its own: keep what it captured.
      _sinceStop
        ..reset()
        ..start();
      unawaited(_finishCapture());
    }
    notifyListeners();
  }

  Future<void> _loadHistory() async {
    try {
      final entries = await _historyService.getHistory();
      _history
        ..clear()
        ..addAll(entries);
      _historyRevision++;
      notifyListeners();
    } catch (e) {
      _logger.error('Failed to load transaction history', error: e);
    }
  }

  void _handleWebSocketMessage(Map<String, dynamic> msg) {
    final event = msg['event'] as String?;
    if (event == 'transcription') {
      _setTranscript(msg['text'] ?? '');
      notifyListeners();
      unawaited(_finishRecordingSession());
    } else if (event == 'error') {
      final errorMsg = msg['message'] ?? 'Unknown error';

      if (msg['error_code'] == 'NO_AUDIO') {
        _errorController.add(
          'No audio detected. Please check your microphone.',
        );
      } else {
        _errorController.add('Server error: $errorMsg');
      }
      _logger.error('Server error: $errorMsg');
    }
  }

  Future<void> _transcribeWithGroq() async {
    _isTranscribing = true;
    notifyListeners();
    try {
      final text = await _groqService.finalizeAndTranscribe();
      _setTranscript(text);
      notifyListeners();
      await _finishRecordingSession();
    } on GroqError catch (e) {
      _errorController.add(e.userMessage);
      _logger.error('Groq transcription failed: ${e.message}');
    } finally {
      _isTranscribing = false;
      notifyListeners();
    }
  }

  Future<void> _finishRecordingSession() async {
    var text = _currentBuffer.trim();
    if (text.isEmpty) return;
    final transcribedAt = _sinceStop.elapsedMilliseconds;

    final profile = _settingsService.dictationProfile;
    if (profile.requiresLlm) {
      final wasTranscribing = _isTranscribing;
      _isTranscribing = true;
      notifyListeners();
      try {
        text = await _transformService.transform(text, profile);
        _setTranscript(text);
        notifyListeners();
      } on GroqError catch (e) {
        _errorController.add(
          '${profile.label} polish unavailable, pasted raw text. ${e.userMessage}',
        );
        _logger.warning(
          'Transform fallback (${profile.storageKey}): ${e.message}',
        );
      } finally {
        if (!wasTranscribing) {
          _isTranscribing = false;
          notifyListeners();
        }
      }
    }

    final timestamp = DateTime.now();

    // Paste first: the user is waiting on it, and a history failure must
    // never cost them the text.
    await _automationService.runAutomation(text);
    _logTiming(transcribedAt);

    if (incognitoMode) return;
    try {
      await _historyService.saveTranscription(text: text, timestamp: timestamp);
      unawaited(_loadHistory());
    } catch (e) {
      _logger.error('Could not save transcript to history', error: e);
    }
  }

  /// One line per dictation: how long after the user stopped the text was
  /// ready and pasted, so a slow one can be told apart (network or polish).
  void _logTiming(int transcribedAt) {
    if (!_sinceStop.isRunning) return;
    _sinceStop.stop();
    final mode = _settingsService.isGroqMode ? 'Groq' : 'server';
    _logger.info(
      'Timing ($mode): transcript ${transcribedAt}ms after stop, '
      'pasted at ${_sinceStop.elapsedMilliseconds}ms',
    );
  }

  /// The single place the transcript changes, so its timestamp cannot drift.
  void _setTranscript(String text) {
    _currentBuffer = text;
    _transcriptAt = text.isEmpty ? null : DateTime.now();
  }

  /// Explicitly clears all sensitive transcription data from memory and disk.
  Future<void> _clearSensitiveData() async {
    _setTranscript('');
    _history.clear();
    _historyRevision++;
    _groqService.clearBuffer();
    _showSilenceWarning = false;
    await _historyService.clearAll();
    _logger.info('Sensitive data purged from memory and disk');
    notifyListeners();
  }
}
