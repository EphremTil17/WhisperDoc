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
import 'package:flutter_client/core/services/auth_service.dart';
import 'websocket/configuration_manager.dart';
import 'websocket/handshake_payload_builder.dart';
import 'websocket/audio_buffer_manager.dart';
import 'websocket/reconnection_manager.dart';
import 'websocket/heartbeat_manager.dart';

enum ConnectionStatus { disconnected, connecting, connected, banned }

/// Lean orchestrator for WebSocket connectivity.
/// Delegates specialized logic to sub-managers for buffering, reconnection, and heartbeats.
class WebSocketService extends ChangeNotifier {
  final SettingsService _settingsService;
  final AuthService _authService;
  
  // Internal Managers
  final TransportSecurityService _transportSecurity = TransportSecurityService();
  final HandshakeStateMachine _handshake = HandshakeStateMachine();
  final BanStateService _banState = BanStateService();
  final HandshakePayloadBuilder _payloadBuilder = HandshakePayloadBuilder();
  final AudioBufferManager _audioBuffer = AudioBufferManager();
  final ReconnectionManager _reconnection = ReconnectionManager();
  final HeartbeatManager _heartbeat = HeartbeatManager();
  late final ConfigurationManager _config;

  WebSocketChannel? _channel;
  final StreamController<ConnectionStatus> _statusController = StreamController<ConnectionStatus>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController = StreamController<Map<String, dynamic>>.broadcast();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  bool _isConnecting = false;
  bool _isAuthenticatedSession = false;
  bool _isIntentionalDisconnect = false;
  String? _lastHandshakeError;
  String? _activeApiKey;
  SecurityStatus _securityStatus = SecurityStatus.secure; // Default to secure

  // State Getters
  ConnectionStatus get status => _status;
  bool get isConnecting => _isConnecting;
  bool get isAuthenticatedSession => _isAuthenticatedSession;
  String? get lastHandshakeError => _lastHandshakeError;
  SecurityStatus get securityStatus => _securityStatus;
  BanStateService get banState => _banState;
  HandshakeStateMachine get handshakeState => _handshake;
  Stream<ConnectionStatus> get onStatusChanged => _statusController.stream;
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;
  LoggingService get _logger => LoggingService();

  /// Returns true if the app has valid credentials (OIDC or API Key) to attempt a connection.
  bool get hasValidCredentials => 
      _authService.isAuthenticated || (_settingsService.cachedApiKey?.isNotEmpty ?? false);

  WebSocketService(this._settingsService, this._authService) {
    _config = ConfigurationManager(_authService, _settingsService);
    
    // Wire up configuration changes
    _config.startObserving(
      onReconnectNeeded: () {
        if (_status == ConnectionStatus.connected || _status == ConnectionStatus.connecting) {
          disconnect(reason: 'Configuration/Identity update required');
        }
      },
      onAutoConnectDesired: () {
        if (_status == ConnectionStatus.disconnected) {
          unawaited(connect());
        }
      },
    );

    _handshake.stateStream.listen((state) {
      if (state == HandshakeState.authenticated) _audioBuffer.flush(_channel!);
      else if (state == HandshakeState.failed) _audioBuffer.clear();
    });
    _logger.attachWebSocket(this);
  }

  @override
  void dispose() {
    _heartbeat.stop();
    _reconnection.stop();
    _config.stopObserving();
    _handshake.dispose();
    _banState.dispose();
    _statusController.close();
    _messageController.close();
    super.dispose();
  }

  // --- External API ---

  Future<bool> connect({String? uriOverride, String? apiKeyOverride}) async {
    if (_status == ConnectionStatus.connected && uriOverride == null && apiKeyOverride == null) return true;
    if (_isConnecting || _banState.isBanned) return false;

    _isConnecting = true;
    _isIntentionalDisconnect = false;
    _lastHandshakeError = null;
    _updateStatus(ConnectionStatus.connecting);
    _handshake.reset();

    try {
      final uriString = uriOverride ?? _settingsService.serverUri;
      _activeApiKey = apiKeyOverride ?? await _settingsService.getApiKey();

      if (!_authService.isAuthenticated && (_activeApiKey?.isEmpty ?? true)) {
        _lastHandshakeError = 'Authentication required';
        _handshake.transitionTo(HandshakeState.failed);
        throw Exception('No authentication available');
      }

      final security = await _transportSecurity.validateServerUri(uriString);
      _securityStatus = security;
      if (security == SecurityStatus.blocked) throw Exception('Security violation');

      _channel = IOWebSocketChannel.connect(Uri.parse(_transportSecurity.normalizeUri(uriString)));
      await _channel!.ready;

      _channel!.stream.listen(_handleRawMessage, onError: _handleSocketError, onDone: _handleSocketClose);
      
      final hello = await _waitForServerHello();
      if (hello == null) throw Exception('Handshake timeout');

      await _sendClientHello();
      _isConnecting = false;
      return true;
    } catch (e) {
      _logger.error('Connection failed', error: e);
      if (e.toString().contains('Auth token missing')) {
        _lastHandshakeError = 'Identity session expired or missing';
        _handshake.transitionTo(HandshakeState.failed);
      }
      _isConnecting = false;
      _handleDisconnect();
      return false;
    }
  }

  Future<void> disconnect({String reason = 'Client closed'}) async {
    _isIntentionalDisconnect = true;
    _reconnection.reset();
    if (_channel != null) await _channel!.sink.close(1000, reason);
  }

  void sendAudioChunk(Uint8List data) {
    if (_handshake.canSendAudio() && _channel != null) {
      _channel!.sink.add(data);
      _heartbeat.reset(onTimeout: () => disconnect(reason: 'Idle'));
    } else if (_handshake.state == HandshakeState.authenticating || _isConnecting) {
      // Buffer chunks while connecting or authenticating to prevent audio loss
      _audioBuffer.add(data);
    }
  }

  void sendEndSignal() => _sendJson({'event': 'end-of-stream'});
  void sendLog(String level, String msg) => _sendJson({'event': 'log', 'level': level, 'message': msg});

  // --- Internal Logic ---

  Future<void> _sendClientHello() async {
    String? token = _authService.isAuthenticated ? await _authService.getAccessToken() : _activeApiKey;
    String authType = _authService.isAuthenticated ? 'oidc' : 'api_key';

    if (token == null) throw Exception('Auth token missing');

    final payload = await _payloadBuilder.buildHello(
      token: token,
      authType: authType,
      incognito: _settingsService.incognitoMode,
    );

    _sendJson(payload);
    _handshake.transitionTo(HandshakeState.authenticating);
  }

  void _handleRawMessage(dynamic data) {
    _heartbeat.reset(onTimeout: () => disconnect(reason: 'Idle'));
    if (data is! String) return;

    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final event = json['event'];

      if (event == 'authenticated') {
        _isAuthenticatedSession = true;
        _handshake.transitionTo(HandshakeState.authenticated);
        _updateStatus(ConnectionStatus.connected);
      } else if (event == 'error' && (json['code'] == 403 || json['message']?.contains('Auth') == true)) {
        _handleAuthError(json['message']);
      } else {
        _messageController.add(json);
      }
    } catch (e) {
      _logger.error('Message parse error', error: e);
    }
  }

  void _handleAuthError(dynamic message) {
    _lastHandshakeError = message?.toString() ?? 'Auth failed';
    _handshake.transitionTo(HandshakeState.failed);
    _isIntentionalDisconnect = true;
    _handleDisconnect();
  }

  void _handleSocketError(dynamic error) => _handleDisconnect();

  void _handleSocketClose() {
    final code = _channel?.closeCode;
    final reason = _channel?.closeReason;

    if (code == 1008) {
      if (reason?.contains('ban') == true) {
        _banState.parseBanMessage(reason);
        _updateStatus(ConnectionStatus.banned);
      } else {
        _handleAuthError(reason);
      }
      return;
    }
    _handleDisconnect();
  }

  void _handleDisconnect() {
    bool wasActive = _status == ConnectionStatus.connected;
    if (_status != ConnectionStatus.banned) _updateStatus(ConnectionStatus.disconnected);
    
    _isAuthenticatedSession = false; // Reset session flag on any disconnect
    _channel = null;
    _heartbeat.stop();
    _isConnecting = false;

    if (!_isIntentionalDisconnect && wasActive && !_banState.isBanned) {
      _reconnection.schedule(
        onRetry: () => connect(),
        lastError: _lastHandshakeError,
        isBanned: _banState.isBanned,
      );
    }
  }

  void _sendJson(Map<String, dynamic> json) {
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(json));
      _heartbeat.reset(onTimeout: () => disconnect(reason: 'Idle'));
    }
  }

  Future<Map<String, dynamic>?> _waitForServerHello() async {
    final completer = Completer<Map<String, dynamic>?>();
    final sub = onMessage.listen((msg) {
      if (msg['event'] == 'hello' && !completer.isCompleted) completer.complete(msg);
    });
    return completer.future.timeout(const Duration(seconds: 5), onTimeout: () {
      sub.cancel();
      return null;
    }).then((val) { sub.cancel(); return val; });
  }

  void _updateStatus(ConnectionStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _statusController.add(newStatus);
      notifyListeners();
    }
  }
}
