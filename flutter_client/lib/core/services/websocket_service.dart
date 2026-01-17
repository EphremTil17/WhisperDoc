import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutter_client/core/services/logging_service.dart';
import 'package:flutter_client/core/services/settings_service.dart';
import 'package:flutter_client/core/services/transport_security_service.dart';
import 'package:flutter_client/core/services/handshake_state_machine.dart';
import 'package:flutter_client/core/services/ban_state_service.dart';
import 'package:flutter_client/core/constants/app_constants.dart';

enum ConnectionStatus { disconnected, connecting, connected, banned }

/// Hardened WebSocket service with integrated security layers.
///
/// Security Features:
/// - Transport Security: WSS enforcement with RFC 1918 validation
/// - Handshake Protocol: Authentication before data transmission
/// - Ban Awareness: 1008 close code handling with cooldown
/// - Audio Buffering: Queue data during handshake, flush after auth
///
/// Matches backend v2.7 security architecture and Python terminal client patterns.
class WebSocketService extends ChangeNotifier {
  final SettingsService _settingsService;
  final TransportSecurityService _transportSecurity =
      TransportSecurityService();
  final HandshakeStateMachine _handshake = HandshakeStateMachine();
  final BanStateService _banState = BanStateService();

  WebSocketChannel? _channel;
  final StreamController<ConnectionStatus> _statusController =
      StreamController<ConnectionStatus>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  LoggingService get _logger => LoggingService();

  SecurityStatus _securityStatus = SecurityStatus.secure; // Default to secure
  SecurityStatus get securityStatus => _securityStatus;

  ConnectionStatus _status = ConnectionStatus.disconnected;
  ConnectionStatus get status => _status;
  Stream<ConnectionStatus> get onStatusChanged => _statusController.stream;
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;

  // Expose ban state for UI
  BanStateService get banState => _banState;
  HandshakeStateMachine get handshakeState => _handshake;

  Timer? _reconnectTimer;
  Timer? _idleTimer;
  bool _isIntentionalDisconnect = false;
  bool _isConnecting = false;

  // Audio buffer with 5s limit (16kHz * 16-bit * 1ch * 5s = ~160KB)
  final List<Uint8List> _pendingAudioBuffer = [];
  static const int _maxBufferSize = 160000; // bytes
  int _currentBufferSize = 0;

  static const Duration idleTimeout = AppConstants.wsIdleTimeout;
  String _lastKnownUri;
  bool _lastKnownIncognito = false;

  WebSocketService(this._settingsService)
    : _lastKnownUri = _settingsService.serverUri,
      _lastKnownIncognito = _settingsService.incognitoMode {
    _settingsService.addListener(_onSettingsChanged);
    LoggingService().attachWebSocket(this);

    // Listen to handshake state changes for logging
    _handshake.stateStream.listen((state) {
      if (state == HandshakeState.authenticated) {
        _flushPendingAudioBuffer();
      } else if (state == HandshakeState.failed) {
        _clearAudioBuffer();
      }
    });
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _reconnectTimer?.cancel();
    _settingsService.removeListener(_onSettingsChanged);
    _handshake.dispose();
    _banState.dispose();
    unawaited(_statusController.close());
    unawaited(_messageController.close());
    super.dispose();
  }

  void _onSettingsChanged() async {
    final currentUri = _settingsService.serverUri;
    final currentIncognito = _settingsService.incognitoMode;

    // If URI changed, trigger reconnect
    if (currentUri != _lastKnownUri) {
      _lastKnownUri = currentUri;
      if (_status == ConnectionStatus.connected ||
          _status == ConnectionStatus.connecting) {
        _logger.info('Server URI changed, reconnecting');
        await disconnect(reason: 'Server URI changed');
      }
      return;
    }

    // If incognito mode changed and connected, force reconnect
    if (currentIncognito != _lastKnownIncognito) {
      _lastKnownIncognito = currentIncognito;
      if (_status == ConnectionStatus.connected) {
        _logger.info(
          'Incognito mode changed, reconnecting with new privacy flag',
        );
        await disconnect(reason: 'Incognito mode toggle');
        // Auto-reconnect will trigger on next audio send
      }
    }
  }

  Future<bool> connect() async {
    if (_status == ConnectionStatus.connected) return true;
    if (_isConnecting) return false;
    if (_banState.isBanned) {
      _logger.warning(
        'Cannot connect: IP is banned for ${_banState.cooldownRemaining}s',
      );
      return false;
    }

    _isConnecting = true;
    _isIntentionalDisconnect = false;
    _updateStatus(ConnectionStatus.connecting);
    _handshake.reset();

    try {
      final uriString = _settingsService.serverUri;

      // 1. Transport Security Validation
      _securityStatus = await _transportSecurity.validateServerUri(uriString);
      if (_securityStatus == SecurityStatus.blocked) {
        _logger.error(
          'Transport security violation: WS connection to public IP blocked',
        );
        _isConnecting = false;
        _handleDisconnect();
        return false;
      }

      final normalizedUri = _transportSecurity.normalizeUri(uriString);
      final uri = Uri.parse(normalizedUri);
      _logger.info('Connecting to WebSocket: $uri (${securityStatus.name})');

      _channel = IOWebSocketChannel.connect(uri);

      // 2. Wait for connection establishment
      await _channel!.ready;
      _logger.info('WebSocket TCP connection established');

      // 3. Set up message listener BEFORE handshake
      _channel!.stream.listen(
        (data) => _handleMessage(data),
        onError: (error) => _handleError(error),
        onDone: () => _handleClose(),
      );

      // 4. Wait for server hello
      final serverHello = await _waitForServerHello();
      if (serverHello == null) {
        throw Exception('Server hello timeout');
      }

      // 5. Send client hello with auth
      await _sendClientHello();

      // 6. Wait for authenticated event (handled by message listener)
      // Handshake state machine will transition to authenticated
      // Connection status updated to connected after authentication

      _isConnecting = false;
      return true;
    } catch (e) {
      _isConnecting = false;
      _logger.error('Connection failed', error: e);
      _handleDisconnect();
      return false;
    }
  }

  Future<Map<String, dynamic>?> _waitForServerHello() async {
    try {
      final completer = Completer<Map<String, dynamic>?>();
      StreamSubscription? sub;

      sub = onMessage.listen((msg) {
        if (msg['event'] == 'hello') {
          unawaited(sub?.cancel());
          completer.complete(msg);
        }
      });

      // 5s timeout for server hello
      Future.delayed(const Duration(seconds: 5), () {
        if (!completer.isCompleted) {
          unawaited(sub?.cancel());
          completer.complete(null);
        }
      });

      final hello = await completer.future;
      if (hello != null) {
        _logger.info('Received server hello: v${hello['version']}');
      }
      return hello;
    } catch (e) {
      _logger.error('Error waiting for server hello', error: e);
      return null;
    }
  }

  Future<void> _sendClientHello() async {
    final apiKey = await _settingsService.getApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('No API key configured');
    }

    final payload = {
      'event': 'hello',
      'client': 'flutter_windows',
      'version': '2.7.0', // Client version matching backend
      'token': apiKey,
      'incognito': _settingsService.incognitoMode,
    };

    _logger.info('Sending client hello (incognito: ${payload['incognito']})');
    _channel?.sink.add(jsonEncode(payload));
    _handshake.transitionTo(HandshakeState.authenticating);
  }

  void _handleMessage(dynamic data) {
    _resetIdleTimer();

    if (data is String) {
      final trimmed = data.trim();
      if (trimmed.startsWith('{')) {
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final event = json['event'] as String?;

          // Handle authentication event
          if (event == 'authenticated') {
            _logger.info('Handshake complete: Authenticated');
            _handshake.transitionTo(HandshakeState.authenticated);
            _updateStatus(ConnectionStatus.connected);
            _resetIdleTimer();
            return;
          }

          // Handle authentication errors
          if (event == 'error') {
            final code = json['code'];
            final message = json['message'];
            if (code == 403 ||
                message?.toString().contains('Authentication') == true) {
              _logger.error('Authentication failed: $message');
              _handshake.transitionTo(HandshakeState.failed);
              _handleDisconnect();
              return;
            }
          }

          // Forward all messages to controller
          _messageController.add(json);
        } catch (e) {
          _logger.error('JSON parse error', error: e);
        }
      } else {
        _logger.warning('Received non-JSON text from server: $data');
      }
    }
  }

  void _handleError(dynamic error) {
    _isConnecting = false;
    _logger.error('WebSocket error', error: error);
    _handleDisconnect();
  }

  void _handleClose() {
    _isConnecting = false;

    // Extract close code and reason
    final closeCode = _channel?.closeCode;
    final closeReason = _channel?.closeReason;

    if (closeCode == 1000 || _isIntentionalDisconnect) {
      // Normal closure or expected disconnect
      _logger.info(
        'WebSocket closed normally (code: ${closeCode ?? 1000}, reason: ${closeReason ?? "Intentional"})',
      );
    } else if (closeCode == 1008) {
      // Protocol violation / Ban / Auth Failure
      _logger.error('Connection closed: 1008 Policy Violation - $closeReason');

      final isBan =
          closeReason?.toLowerCase().contains('ban') == true ||
          closeReason?.toLowerCase().contains('cooldown') == true ||
          closeReason?.toLowerCase().contains('retry') == true;

      if (isBan) {
        _banState.parseBanMessage(closeReason);
        _handshake.transitionTo(HandshakeState.banned);
        _updateStatus(ConnectionStatus.banned);
      } else {
        // Assume authentication or policy failure if doesn't look like a ban
        _handshake.transitionTo(HandshakeState.failed);
        _updateStatus(ConnectionStatus.disconnected);

        // Notify of auth failure
        _messageController.add({
          'event': 'error',
          'code': 'AUTH_FAILED',
          'message': closeReason ?? 'Authentication refused by server',
        });
      }

      _isIntentionalDisconnect = true; // Disable auto-reconnect
      _clearReconnectState();
    } else {
      _logger.warning(
        'WebSocket closed unexpectedly (code: $closeCode, reason: $closeReason)',
      );
    }

    _handleDisconnect();
  }

  void _handleDisconnect() {
    final wasActive =
        _status != ConnectionStatus.disconnected &&
        _status != ConnectionStatus.banned;

    if (_status != ConnectionStatus.banned) {
      _updateStatus(ConnectionStatus.disconnected);
    }

    _channel = null;
    _idleTimer?.cancel();
    _isConnecting = false;
    _handshake.reset();

    // Auto-reconnect only if not intentional and not banned
    if (!_isIntentionalDisconnect && wasActive && !_banState.isBanned) {
      _scheduleReconnect();
    }
  }

  void sendAudioChunk(Uint8List data) {
    // Audio can only be sent after authentication
    if (_handshake.canSendAudio() && _channel != null) {
      try {
        _channel!.sink.add(data);
        _resetIdleTimer();
      } catch (e) {
        _logger.error('Failed to send audio', error: e);
      }
    } else if (_handshake.state == HandshakeState.authenticating) {
      // Buffer audio during handshake (with size limit)
      if (_currentBufferSize < _maxBufferSize) {
        _pendingAudioBuffer.add(data);
        _currentBufferSize += data.length;
      } else {
        _logger.warning('Audio buffer full, dropping chunk');
      }
    } else {
      _logger.warning('Cannot send audio in ${_handshake.state.name} state');
    }
  }

  void sendEndSignal() {
    if (_handshake.canSendAudio() && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode({'event': 'end-of-stream'}));
        _resetIdleTimer();
      } catch (e) {
        _logger.error('Failed to send end signal', error: e);
      }
    }
  }

  void sendLog(String level, String message) {
    if (_handshake.canSendAudio() && _channel != null) {
      try {
        _channel!.sink.add(
          jsonEncode({'event': 'log', 'level': level, 'message': message}),
        );
      } catch (e) {
        // Silently fail - avoid infinite logging loop
      }
    }
  }

  Future<void> disconnect({String reason = 'Client reconnecting'}) async {
    _isIntentionalDisconnect = true;
    _clearReconnectState();
    // Close with code 1000 (Normal Closure)
    if (_channel != null) {
      await _channel!.sink.close(1000, reason);
    }
  }

  // --- Private Helper Methods ---

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, () {
      _logger.info('Idle timeout reached, closing connection');
      unawaited(disconnect(reason: 'Idle timeout'));
    });
  }

  void _flushPendingAudioBuffer() {
    if (_pendingAudioBuffer.isEmpty) return;

    _logger.info(
      'Flushing ${_pendingAudioBuffer.length} buffered audio chunks',
    );
    for (final chunk in _pendingAudioBuffer) {
      _channel?.sink.add(chunk);
    }
    _clearAudioBuffer();
  }

  void _clearAudioBuffer() {
    _pendingAudioBuffer.clear();
    _currentBufferSize = 0;
  }

  int _reconnectAttempts = 0;
  static const int _maxReconnectDelay = 30;

  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive ?? false) return;
    if (_banState.isBanned) return;

    final delaySeconds = (3 * (1 << _reconnectAttempts)).clamp(
      3,
      _maxReconnectDelay,
    );

    _logger.info(
      'Reconnect scheduled in ${delaySeconds}s (Attempt ${_reconnectAttempts + 1})',
    );

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _reconnectAttempts++;
      unawaited(connect());
    });
  }

  void _clearReconnectState() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
  }

  void _updateStatus(ConnectionStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _statusController.add(newStatus);
      notifyListeners();
    }
  }
}
