import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'logging_service.dart';

enum ConnectionStatus { disconnected, connecting, connected }

class WebSocketService {
  final String url;
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
  bool _isIntentionalDisconnect = false;

  WebSocketService({this.url = 'ws://localhost:9989/ws'}) {
    // Attach self to the logger so it can send logs out
    LoggingService().attachWebSocket(this);
  }

  void connect() {
    if (_status == ConnectionStatus.connected ||
        _status == ConnectionStatus.connecting) {
      return;
    }

    _isIntentionalDisconnect = false;
    _updateStatus(ConnectionStatus.connecting);

    try {
      _channel = WebSocketChannel.connect(Uri.parse(url));

      _channel!.stream.listen(
        (data) {
          _updateStatus(ConnectionStatus.connected);
          if (data is String) {
            try {
              final json = jsonDecode(data);
              _messageController.add(json);
            } catch (e) {
              _logger.error(
                'JSON Parse Error: $e',
                sendToServer: false,
              ); // Don't send socket errors to socket
            }
          }
        },
        onError: (error) {
          _logger.error('WebSocket Error: $error', sendToServer: false);
          _handleDisconnect();
        },
        onDone: () {
          _logger.warning('WebSocket Closed', sendToServer: false);
          _handleDisconnect();
        },
      );
    } catch (e) {
      _logger.error('Connection failed: $e', sendToServer: false);
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _updateStatus(ConnectionStatus.disconnected);
    _channel = null;

    if (!_isIntentionalDisconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null && _reconnectTimer!.isActive) {
      return;
    }

    _logger.info('Scheduling reconnect in 3 seconds...', sendToServer: false);
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      connect();
    });
  }

  void sendAudioChunk(Uint8List data) {
    if (_status == ConnectionStatus.connected && _channel != null) {
      try {
        _channel!.sink.add(data);
      } catch (e) {
        _logger.error('Failed to send audio: $e', sendToServer: false);
      }
    }
  }

  void sendEndSignal() {
    if (_status == ConnectionStatus.connected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode({'event': 'end-of-stream'}));
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
