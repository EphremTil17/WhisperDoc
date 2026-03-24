import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_client/logic/models/transcription_entry.dart';
import 'package:flutter_client/services/hardware/audio_service.dart';
import 'package:flutter_client/services/utility/automation_service.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/hardware/audio_cue_service.dart';
import 'package:flutter_client/services/utility/history_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/transcription/groq_transcription_service.dart';
import 'package:flutter_client/services/transcription/groq_error.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/processors/transcription_processor.dart';
import 'package:flutter_client/logic/processors/audio_signal_processor.dart';

/// Controller managing recording state, transcription, and automation.
///
/// Orchestrates audio capture, WebSocket communication, and post-processing.
class RecordingController extends ChangeNotifier {
  final AudioService _audioService;
  final WebSocketService _wsService;
  final GroqTranscriptionService _groqService;
  final AutomationService _automationService;
  final HistoryService _historyService;
  final SettingsService _settingsService;
  final AudioCueService _audioCueService;
  final TranscriptionProcessor _processor;
  final AudioSignalProcessor _signalProcessor = AudioSignalProcessor();

  StreamSubscription? _audioSubscription;
  StreamSubscription? _messageSubscription;

  // Buffer of transcription segments (limited to prevent memory issues)
  final List<TranscriptionEntry> _history = [];

  // Current active transcription buffer (accumulating text)
  String _currentBuffer = '';
  bool _awaitingFinalTranscription = false;

  // Single source of truth for recording state
  bool _isRecording = false;

  // Liveness check - warning if no audio signal is detected
  bool _showSilenceWarning = false;
  bool get showSilenceWarning => _showSilenceWarning;

  // Groq transcription lockout — single source of truth for all UI/hotkey paths
  bool _isTranscribing = false;
  bool get isTranscribing => _isTranscribing;

  // Incognito mode - when ON, transcriptions are not saved to history
  bool get incognitoMode => _settingsService.incognitoMode;

  RecordingController({
    required AudioService audioService,
    required WebSocketService wsService,
    required GroqTranscriptionService groqService,
    required AutomationService automationService,
    required HistoryService historyService,
    required SettingsService settingsService,
    required AudioCueService audioCueService,
  }) : _audioService = audioService,
       _wsService = wsService,
       _groqService = groqService,
       _automationService = automationService,
       _historyService = historyService,
       _settingsService = settingsService,
       _audioCueService = audioCueService,
       _processor = TranscriptionProcessor(historyService, automationService) {
    _initListeners();
    // Listen to AudioService state changes
    _audioService.addListener(_onAudioStateChanged);
    // Sync with settings changes
    _settingsService.addListener(notifyListeners);
    // Load initial history from encrypted storage
    unawaited(_loadHistory());
  }

  Future<void> _loadHistory() async {
    try {
      final entries = await _historyService.getHistory();
      _history.clear();
      _history.addAll(entries);
      notifyListeners();
    } catch (e) {
      LoggingService().error('Failed to load transaction history', error: e);
    }
  }

  /// Helper to get decrypted text for an entry (used by UI)
  String getDecryptedText(TranscriptionEntry entry) {
    return _historyService.decryptEntry(entry);
  }

  // Getters
  String get currentText => _currentBuffer;
  bool get isRecording => _isRecording;
  List<TranscriptionEntry> get history => List.unmodifiable(_history);

  /// Enables incognito mode and clears existing history
  Future<void> enableIncognitoMode() async {
    await _settingsService.setIncognitoMode(true);
    await _clearSensitiveData();
    LoggingService().info(
      'Incognito mode enabled - history and buffers cleared',
    );
  }

  /// Disables incognito mode (history recording resumes)
  Future<void> disableIncognitoMode() async {
    await _settingsService.setIncognitoMode(false);
    unawaited(_loadHistory());
    LoggingService().info('Incognito mode disabled - history restored');
  }

  /// Clears all transcription history
  Future<void> clearHistory() async {
    await _historyService.clearAll();
    await _loadHistory();
  }

  void _onAudioStateChanged() {
    if (_isRecording != _audioService.isRecording) {
      _isRecording = _audioService.isRecording;
      notifyListeners();
    }
  }

  void _initListeners() {
    _messageSubscription = _wsService.onMessage.listen(_handleWebSocketMessage);
  }

  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  Stream<String> get onError => _errorController.stream;

  void _handleWebSocketMessage(Map<String, dynamic> msg) {
    if (msg.containsKey('text') && !msg.containsKey('event')) {
      final text = msg['text'] as String;
      _currentBuffer = _processor.appendText(_currentBuffer, text);
      notifyListeners();

      if (_awaitingFinalTranscription) {
        unawaited(_finishRecordingSession());
      }
      return;
    }

    final event = msg['event'] as String?;
    if (event == 'transcription') {
      _currentBuffer = msg['text'] ?? '';
      _awaitingFinalTranscription = false;
      notifyListeners();
      unawaited(_finishRecordingSession());
    } else if (event == 'error') {
      _awaitingFinalTranscription = false;
      final code = msg['code']?.toString();
      final errorMsg = msg['message'] ?? msg['error'] ?? 'Unknown error';

      if (code == 'NO_AUDIO') {
        _errorController.add(
          'No audio detected. Please check your microphone.',
        );
      } else {
        _errorController.add('Server error: $errorMsg');
      }
      LoggingService().error('Server error: $errorMsg', sendToServer: false);
    }
  }

  Future<void> toggleRecording() async {
    if (_isRecording) {
      await stopRecording();
    } else {
      await startRecording();
    }
  }

  Future<void> startRecording() async {
    // Groq transcription lockout — prevent hotkey/capsule race during upload.
    if (_isTranscribing) return;

    _currentBuffer = '';
    _awaitingFinalTranscription = false;
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
      final String? deviceId = _settingsService.microphoneId;
      final String? deviceLabel = _settingsService.microphoneLabel;

      await _audioService.startRecording(
        deviceId: deviceId,
        deviceLabel: deviceLabel,
      );
      _audioCueService.playStartCue();

      notifyListeners();

      // 3. Mode-aware audio piping.
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
        unawaited(
          _wsService.ensureConnected().then((connected) {
            if (!connected && _isRecording) {
              unawaited(stopRecording());
              _errorController.add('Failed to wake up server connection.');
            }
          }),
        );
      }

      // 4. Liveness Probe (Reactive Silence Detection) — both modes.
      unawaited(
        _signalProcessor.detectSilence(_audioService.amplitudeStream).then((
          isSilent,
        ) {
          if (isSilent && _isRecording) {
            _showSilenceWarning = true;
            notifyListeners();
            LoggingService().warning(
              'No audio detected after 3 seconds. Virtual driver conflict suspected.',
            );
          }
        }),
      );
    } catch (e) {
      LoggingService().error('Failed to start recording', error: e);
      _isRecording = false;
      notifyListeners();
    }
  }

  Future<void> stopRecording() async {
    await _audioService.stopRecording();
    _audioCueService.playStopCue();
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    if (_settingsService.isGroqMode) {
      unawaited(_transcribeWithGroq());
    } else {
      _wsService.sendEndSignal();
      _awaitingFinalTranscription = true;
    }
  }

  Future<void> _transcribeWithGroq() async {
    _isTranscribing = true;
    notifyListeners();
    try {
      final text = await _groqService.finalizeAndTranscribe();
      _currentBuffer = text;
      notifyListeners();
      unawaited(_finishRecordingSession());
    } on GroqError catch (e) {
      _errorController.add(e.userMessage);
      LoggingService().error(
        'Groq transcription failed: ${e.message}',
        sendToServer: false,
      );
    } finally {
      _isTranscribing = false;
      notifyListeners();
    }
  }

  Future<void> _finishRecordingSession() async {
    _awaitingFinalTranscription = false;
    final text = _currentBuffer.trim();

    if (text.isNotEmpty) {
      final timestamp = DateTime.now();

      // Only add to history if not in incognito mode
      if (!incognitoMode) {
        await _historyService.saveTranscription(
          text: text,
          timestamp: timestamp,
        );
        // Refresh local history view
        unawaited(_loadHistory());
      }

      await _automationService.runAutomation(text);
    }
  }

  @override
  void dispose() {
    unawaited(_clearSensitiveData());
    _audioService.removeListener(_onAudioStateChanged);
    _settingsService.removeListener(notifyListeners);
    unawaited(_audioSubscription?.cancel());
    unawaited(_messageSubscription?.cancel());
    unawaited(_errorController.close());
    super.dispose();
  }

  /// Explicitly clears all sensitive transcription data from memory and disk.
  Future<void> _clearSensitiveData() async {
    _currentBuffer = '';
    _history.clear();
    _showSilenceWarning = false;
    await _historyService.clearAll();
    LoggingService().info('Sensitive data purged from memory and disk');
    notifyListeners();
  }
}
