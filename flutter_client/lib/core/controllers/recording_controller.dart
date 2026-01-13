import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_client/core/models/transcription_entry.dart';
import 'package:flutter_client/core/services/audio_service.dart';
import 'package:flutter_client/core/services/automation_service.dart';
import 'package:flutter_client/core/services/logging_service.dart';
import 'package:flutter_client/core/services/websocket_service.dart';
import 'package:flutter_client/core/constants/app_constants.dart';

/// Controller managing recording state, transcription, and automation.
///
/// Orchestrates audio capture, WebSocket communication, and post-processing.
class RecordingController extends ChangeNotifier {
  final AudioService _audioService;
  final WebSocketService _wsService;
  final AutomationService _automationService;

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
  bool _incognitoMode = false;

  RecordingController({
    required AudioService audioService,
    required WebSocketService wsService,
    required AutomationService automationService,
  }) : _audioService = audioService,
       _wsService = wsService,
       _automationService = automationService {
    _initListeners();
    // Listen to AudioService state changes
    _audioService.addListener(_onAudioStateChanged);
  }

  // Getters
  String get currentText => _currentBuffer;
  bool get isRecording => _isRecording;
  bool get incognitoMode => _incognitoMode;
  List<TranscriptionEntry> get history => List.unmodifiable(_history);

  /// Enables incognito mode and clears existing history
  void enableIncognitoMode() {
    _incognitoMode = true;
    _history.clear();
    LoggingService().info('Incognito mode enabled - history cleared');
    notifyListeners();
  }

  /// Disables incognito mode (history recording resumes)
  void disableIncognitoMode() {
    _incognitoMode = false;
    LoggingService().info('Incognito mode disabled');
    notifyListeners();
  }

  /// Clears all transcription history
  void clearHistory() {
    _history.clear();
    notifyListeners();
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

  void _handleWebSocketMessage(Map<String, dynamic> msg) {
    if (msg.containsKey('text')) {
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
    } else if (msg.containsKey('event')) {
      final event = msg['event'] as String;
      if (event == 'error') {
        _awaitingFinalTranscription = false;
        final errorMsg = msg['message'] ?? msg['code'] ?? 'Unknown error';
        LoggingService().error('Server error: $errorMsg', sendToServer: false);
      }
    } else if (msg.containsKey('error')) {
      _awaitingFinalTranscription = false;
      LoggingService().error(
        'Server error: ${msg['error']}',
        sendToServer: false,
      );
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
      final entry = TranscriptionEntry(text: text, timestamp: DateTime.now());

      // Only add to history if not in incognito mode
      if (!_incognitoMode) {
        _history.add(entry);
        // Enforce max history size
        if (_history.length > AppConstants.maxHistorySize) {
          _history.removeAt(0);
        }
      }
      await _automationService.runAutomation(entry);
    }
  }

  @override
  void dispose() {
    _audioService.removeListener(_onAudioStateChanged);
    unawaited(_audioSubscription?.cancel());
    unawaited(_messageSubscription?.cancel());
    super.dispose();
  }
}
