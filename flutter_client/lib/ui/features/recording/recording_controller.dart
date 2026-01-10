import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_client/core/models/transcription_entry.dart';
import 'package:flutter_client/core/services/audio_service.dart';
import 'package:flutter_client/core/services/automation_service.dart';
import 'package:flutter_client/core/services/logging_service.dart';

import 'package:flutter_client/core/services/websocket_service.dart';

class RecordingController extends ChangeNotifier {
  final AudioService _audioService;
  final WebSocketService _wsService;

  final AutomationService _automationService;

  StreamSubscription? _audioSubscription;
  StreamSubscription? _messageSubscription;

  // Buffer of transcription segments
  final List<TranscriptionEntry> _history = [];

  // Current active transcription buffer (accumulating text)
  String _currentBuffer = '';
  bool _awaitingFinalTranscription = false;

  // Single source of truth for recording state
  bool _isRecording = false;

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
  List<TranscriptionEntry> get history => List.unmodifiable(_history);

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
        // Error handling could be improved to expose an error stream to UI
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
    if (_audioService.isRecording) {
      await stopRecording();
    } else {
      await startRecording();
    }
  }

  Future<void> startRecording() async {
    _currentBuffer = ''; // Clear buffer for new recording
    _awaitingFinalTranscription = false;
    notifyListeners();

    if (_wsService.status != ConnectionStatus.connected) {
      await _wsService.connect();
    }

    await _audioService.startRecording();

    // Pipe audio to websocket
    _audioSubscription = _audioService.audioStream.listen((data) {
      _wsService.sendAudioChunk(data);
    });
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

      _history.add(entry);
      await _automationService.runAutomation(entry);

      // NOTE: We no longer clear the buffer here so users can see/copy the text.
      // Buffer is cleared when startRecording() is called for a new session.
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
