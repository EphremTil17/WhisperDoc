import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutter_client/core/services/logging_service.dart';
import 'package:flutter_client/core/services/settings_service.dart';

enum ConnectionStatus { disconnected, connecting, connected }

class WebSocketService extends ChangeNotifier {
  final SettingsService _settingsService;
  WebSocketChannel? _channel;
  final StreamController<ConnectionStatus> _statusController =
      StreamController<ConnectionStatus>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  // Use a getter to access the singleton
  LoggingService get _logger => LoggingService();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  ConnectionStatus get status => _status;
  Stream<ConnectionStatus> get onStatusChanged => _statusController.stream;
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;

  Timer? _reconnectTimer;
  Timer? _idleTimer;
  bool _isIntentionalDisconnect = false;
  bool _isConnecting = false;

  // High-performance buffer for audio chunks captured while connecting
  final List<Uint8List> _pendingAudioBuffer = [];

  // 5 Minute Idle Timeout
  static const Duration idleTimeout = Duration(minutes: 5);

  // Track last known URI for selective reconnect
  String _lastKnownUri;

  WebSocketService(this._settingsService)
    : _lastKnownUri = _settingsService.serverUri {
    // Listen for settings changes to reconnect if URI changes
    _settingsService.addListener(_onSettingsChanged);
    // Attach self to the logger so it can send logs out
    LoggingService().attachWebSocket(this);
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, () {
      _logger.info(
        'Idle timeout reached (5m). Closing connection to save resources.',
        sendToServer: false,
      );
      disconnect();
    });
  }

  void _flushPendingBuffer() {
    if (_pendingAudioBuffer.isEmpty) return;
    _logger.info(
      'Flushing ${_pendingAudioBuffer.length} buffered chunks to server...',
      sendToServer: false,
    );

    for (final chunk in _pendingAudioBuffer) {
      _channel?.sink.add(chunk);
    }
    _pendingAudioBuffer.clear();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _reconnectTimer?.cancel();
    _settingsService.removeListener(_onSettingsChanged);
    unawaited(_statusController.close());
    unawaited(_messageController.close());
    super.dispose();
  }

  void _onSettingsChanged() {
    final currentUri = _settingsService.serverUri;
    if (currentUri == _lastKnownUri) {
      return; // No URI change, ignore other settings
    }
    _lastKnownUri = currentUri;

    if (_status == ConnectionStatus.connected ||
        _status == ConnectionStatus.connecting) {
      LoggingService().info('Server URI changed, reconnecting...');
      disconnect();
      // We don't auto-reconnect here, let the next interaction handle it
    }
  }

  Future<bool> connect() async {
    if (_status == ConnectionStatus.connected) return true;
    if (_isConnecting) return false;

    _isConnecting = true;
    _isIntentionalDisconnect = false;
    _updateStatus(ConnectionStatus.connecting);

    try {
      final uri = Uri.parse(_settingsService.serverUri);
      _logger.info('Connecting to WebSocket: $uri', sendToServer: false);

      _channel = IOWebSocketChannel.connect(uri);

      // Handle connection success
      final connected = await _channel!.ready
          .then((_) {
            _isConnecting = false;
            _updateStatus(ConnectionStatus.connected);
            _logger.info('WebSocket Connected', sendToServer: false);
            _resetIdleTimer();
            _flushPendingBuffer();
            return true;
          })
          .catchError((e) {
            _isConnecting = false;
            _logger.error(
              'WebSocket connection failed: $e',
              sendToServer: false,
            );
            _handleDisconnect();
            return false;
          });

      _channel!.stream.listen(
        (data) {
          _resetIdleTimer();
          if (data is String) {
            final trimmed = data.trim();
            if (trimmed.startsWith('{')) {
              try {
                final json = jsonDecode(data);
                _messageController.add(json);
              } catch (e) {
                _logger.error('JSON Parse Error: $e', sendToServer: false);
              }
            } else {
              _logger.warning(
                'Received non-JSON text from server: $data',
                sendToServer: false,
              );
            }
          }
        },
        onError: (error) {
          _isConnecting = false;
          _logger.error('WebSocket Error: $error', sendToServer: false);
          _handleDisconnect();
        },
        onDone: () {
          _isConnecting = false;
          _logger.warning('WebSocket Closed', sendToServer: false);
          _handleDisconnect();
        },
      );

      return connected;
    } catch (e) {
      _isConnecting = false;
      _logger.error('Connection failed: $e', sendToServer: false);
      _handleDisconnect();
      return false;
    }
  }

  void _handleDisconnect() {
    _updateStatus(ConnectionStatus.disconnected);
    _channel = null;
    _idleTimer?.cancel();
    _isConnecting = false;

    // Reconnect if we were in the middle of something and it wasn't intentional
    if (!_isIntentionalDisconnect && _status != ConnectionStatus.disconnected) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive ?? false) return;

    _logger.info('Reconnect scheduled...', sendToServer: false);
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      // ignore: discarded_futures
      connect();
    });
  }

  void sendAudioChunk(Uint8List data) {
    if (_status == ConnectionStatus.connected && _channel != null) {
      try {
        _channel!.sink.add(data);
        _resetIdleTimer();
      } catch (e) {
        _logger.error('Failed to send audio: $e', sendToServer: false);
      }
    } else {
      // Buffer the audio if we are still connecting
      _pendingAudioBuffer.add(data);

      // Auto-trigger connection if we aren't already
      if (!_isConnecting && _status == ConnectionStatus.disconnected) {
        // ignore: discarded_futures
        connect();
      }
    }
  }

  void sendEndSignal() {
    if (_status == ConnectionStatus.connected && _channel != null) {
      try {
        _channel!.sink.add('{"event": "end-of-stream"}');
        _resetIdleTimer();
      } catch (e) {
        _logger.error('Failed to send end signal: $e', sendToServer: false);
      }
    }
  }

  /// Sends a log message to the backend.
  /// Format: {"event": "log", "level": "INFO", "message": "..."}
  void sendLog(String level, String message) {
    if (_status == ConnectionStatus.connected && _channel != null) {
      try {
        _channel!.sink.add(
          jsonEncode({'event': 'log', 'level': level, 'message': message}),
        );
      } catch (e) {
        // If sending log fails, we can't really log it to server, so just print locally
        // ignore: avoid_print
        print('Failed to send log packet: $e');
      }
    }
  }

  void disconnect() {
    _isIntentionalDisconnect = true;
    _reconnectTimer?.cancel();
    // ignore: discarded_futures
    _channel?.sink.close();
    _channel = null;
    _updateStatus(ConnectionStatus.disconnected);
  }

  void _updateStatus(ConnectionStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _statusController.add(newStatus);
    }
  }
}
