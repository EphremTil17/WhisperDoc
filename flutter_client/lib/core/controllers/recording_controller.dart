import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_client/core/models/transcription_entry.dart';
import 'package:flutter_client/core/services/audio_service.dart';
import 'package:flutter_client/core/services/automation_service.dart';
import 'package:flutter_client/core/services/logging_service.dart';
import 'package:flutter_client/core/services/websocket_service.dart';
import 'package:flutter_client/core/services/history_service.dart';
import 'package:flutter_client/core/services/settings_service.dart';

/// Controller managing recording state, transcription, and automation.
///
/// Orchestrates audio capture, WebSocket communication, and post-processing.
class RecordingController extends ChangeNotifier {
  final AudioService _audioService;
  final WebSocketService _wsService;
  final AutomationService _automationService;
  final HistoryService _historyService;
  final SettingsService _settingsService;

  StreamSubscription? _audioSubscription;
  StreamSubscription? _messageSubscription;

  // Buffer of transcription segments (limited to prevent memory issues)
  final List<TranscriptionEntry> _history = [];

  // Current active transcription buffer (accumulating text)
  String _currentBuffer = '';
  bool _awaitingFinalTranscription = false;

  // Single source of truth for recording state
  bool _isRecording = false;

  // Incognito mode - when ON, transcriptions are not saved to history
  bool get incognitoMode => _settingsService.incognitoMode;

  RecordingController({
    required AudioService audioService,
    required WebSocketService wsService,
    required AutomationService automationService,
    required HistoryService historyService,
    required SettingsService settingsService,
  }) : _audioService = audioService,
       _wsService = wsService,
       _automationService = automationService,
       _historyService = historyService,
       _settingsService = settingsService {
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
      if (text.trim().isEmpty) return;

      if (_currentBuffer.isEmpty) {
        _currentBuffer = text;
      } else {
        _currentBuffer += ' $text';
      }
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
    _currentBuffer = '';
    _awaitingFinalTranscription = false;
    notifyListeners();

    try {
      // Connect to server if not already connected
      if (_wsService.status != ConnectionStatus.connected) {
        LoggingService().info('Connecting to WebSocket server...');
        final connected = await _wsService.connect();
        if (!connected) {
          LoggingService().error('Failed to connect to WebSocket server');
          return;
        }
      }

      await _audioService.startRecording();

      // Pipe audio to websocket
      _audioSubscription = _audioService.audioStream.listen((data) {
        _wsService.sendAudioChunk(data);
      });
    } catch (e) {
      LoggingService().error('Failed to start recording', error: e);
      _isRecording = false;
      notifyListeners();
    }
  }

  Future<void> stopRecording() async {
    await _audioService.stopRecording();
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    _wsService.sendEndSignal();
    _awaitingFinalTranscription = true;
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
    await _historyService.clearAll();
    LoggingService().info('Sensitive data purged from memory and disk');
    notifyListeners();
  }
}
