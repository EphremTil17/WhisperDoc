import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocket;
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/transport/transport_security_service.dart';
import 'package:flutter_client/services/transport/handshake_state_machine.dart';
import 'package:flutter_client/services/transport/ban_state_service.dart';
import 'package:flutter_client/services/auth/auth_service.dart';
import 'configuration_manager.dart';
import 'handshake_payload_builder.dart';
import 'audio_buffer_manager.dart';
import 'heartbeat_manager.dart';
import 'reconnection_manager.dart';

/// Lean orchestrator for WebSocket connectivity.
/// Delegates specialized logic to sub-managers for buffering, reconnection, and heartbeats.
class WebSocketService extends ChangeNotifier {
  static const int _normalCloseCode = 1000;
  static const int _authForbiddenCode = 403;
  static const int _policyViolationCode = 1008;
  static const int _serverIdleCloseCode = 4001;

  final SettingsService _settingsService;
  final AuthService _authService;

  // Internal Managers
  final TransportSecurityService _transportSecurity =
      TransportSecurityService();
  final HandshakeStateMachine _handshake = HandshakeStateMachine();
  final BanStateService _banState = BanStateService();
  final HandshakePayloadBuilder _payloadBuilder = HandshakePayloadBuilder();
  final AudioBufferManager _audioBuffer = AudioBufferManager();
  final ReconnectionManager _reconnection = ReconnectionManager();
  final HeartbeatManager _heartbeat = HeartbeatManager();
  final ConfigurationManager _config;

  WebSocketChannel? _channel;
  final StreamController<ConnectionStatus> _statusController =
      StreamController<ConnectionStatus>.broadcast();
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  bool _isConnecting = false;
  bool _isAuthenticatedSession = false;
  bool _isIntentionalDisconnect = false;
  bool _pendingConfigChange = false;
  String? _lastHandshakeError;
  String? _activeApiKey;
  SecurityStatus _securityStatus = SecurityStatus.secure; // Default to secure
  String? _backendMinVersion;
  String? _backendSecVersion;
  String? _backendServerVersion;
  String? _connectionId;

  // State Getters
  ConnectionStatus get status => _status;
  bool get isConnecting => _isConnecting;
  bool get isAuthenticatedSession => _isAuthenticatedSession;
  String? get lastHandshakeError => _lastHandshakeError;
  SecurityStatus get securityStatus => _securityStatus;
  BanStateService get banState => _banState;
  HandshakeStateMachine get handshakeState => _handshake;
  String? get backendMinVersion => _backendMinVersion;
  String? get backendSecVersion => _backendSecVersion;
  String? get backendServerVersion => _backendServerVersion;
  String? get connectionId => _connectionId;
  Stream<ConnectionStatus> get onStatusChanged => _statusController.stream;
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;
  bool get hasValidCredentials =>
      _authService.isAuthenticated ||
      (_settingsService.cachedApiKey?.isNotEmpty ?? false);

  @visibleForTesting
  bool get pendingConfigChangeForTesting => _pendingConfigChange;

  @visibleForTesting
  ReconnectionManager get reconnectionManagerForTesting => _reconnection;

  /// Exposes the audio buffer so tests can inspect whether it was flushed or cleared.
  @visibleForTesting
  AudioBufferManager get audioBufferForTesting => _audioBuffer;

  LoggingService get _logger => LoggingService();

  @visibleForTesting
  set pendingConfigChangeForTesting(bool value) => _pendingConfigChange = value;

  @visibleForTesting
  set channelForTesting(WebSocketChannel? channel) => _channel = channel;

  WebSocketService(this._settingsService, this._authService)
    : _config = ConfigurationManager(_authService, _settingsService) {
    // Wire up configuration changes
    _config.startObserving(
      onReconnectNeeded: () {
        if (_status == ConnectionStatus.connected) {
          unawaited(
            disconnect(reason: 'Configuration/Identity update required'),
          );
        } else if (_status == ConnectionStatus.connecting) {
          // Can't safely tear down a half-open connection; remember to apply
          // the new config once the current attempt settles.
          _pendingConfigChange = true;
        }
      },
      onAutoConnectDesired: () {
        if (_status == ConnectionStatus.disconnected) {
          unawaited(connect());
        }
      },
    );

    // Only clear on failure here. Flush on success is handled explicitly in
    // _handleRawMessage so the _pendingConfigChange guard runs before any audio
    // is written to the channel.
    _handshake.stateStream.listen((state) {
      if (state == HandshakeState.failed) {
        _audioBuffer.clear();
      }
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
    unawaited(_statusController.close());
    unawaited(_messageController.close());
    super.dispose();
  }

  // --- External API ---

  Future<bool> connect({String? uriOverride, String? apiKeyOverride}) async {
    if (_status == ConnectionStatus.connected &&
        uriOverride == null &&
        apiKeyOverride == null) {
      return true;
    }
    if (_isConnecting || _banState.isBanned) return false;

    _isConnecting = true;
    _isIntentionalDisconnect = false;
    _lastHandshakeError = null;
    _updateStatus(ConnectionStatus.connecting);
    notifyListeners();
    _handshake.reset();

    try {
      final uriString = uriOverride ?? _settingsService.serverUri;
      _activeApiKey = apiKeyOverride ?? await _settingsService.getApiKey();

      _logger.info(
        'Connecting to: $uriString (Auth: ${_authService.isAuthenticated ? "OIDC" : "API_KEY"})',
      );
      if (!_authService.isAuthenticated && (_activeApiKey?.isEmpty ?? true)) {
        _lastHandshakeError = 'Authentication required';
        _handshake.transitionTo(HandshakeState.failed);
        throw Exception('No authentication available');
      }

      final security = await _transportSecurity.validateServerUri(uriString);
      _securityStatus = security;
      if (security == SecurityStatus.blocked) {
        throw Exception('Security violation');
      }

      // Open the socket manually so we can set pingInterval before handing
      // it to the channel. Dart's IOWebSocketChannel.connect() convenience
      // constructor does not expose this — but the underlying dart:io WebSocket
      // sends protocol-level ping frames automatically when pingInterval is set,
      // Python's websockets library does this by default (every 20 s); we match
      // that behaviour here so the Flutter client stays connected as long as the
      // terminal client does under the same tunnel.
      final socket = await WebSocket.connect(
        _transportSecurity.normalizeUri(uriString),
      );
      socket.pingInterval = const Duration(seconds: 30);
      _channel = IOWebSocketChannel(socket);
      final ch = _channel;
      if (ch == null) throw Exception('Channel not initialized');
      await ch.ready;

      ch.stream.listen(
        _handleRawMessage,
        onError: _handleSocketError,
        onDone: _handleSocketClose,
      );

      final hello = await _waitForServerHello();
      if (hello == null) throw Exception('Handshake timeout');

      // _pendingConfigChange is checked in _handleRawMessage when the
      // 'authenticated' event arrives — the first moment _status is confirmed
      // connected. Nothing useful can be checked here while still connecting.
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
      _handleDisconnect(); // consumes _pendingConfigChange for the failure path

      return false;
    }
  }

  Future<void> disconnect({String reason = 'Client closed'}) async {
    _isIntentionalDisconnect = true;
    _reconnection.reset();
    _logger.info('Disconnect requested by client | Reason: $reason');
    final ch = _channel;
    if (ch != null) await ch.sink.close(_normalCloseCode, reason);
  }

  /// Ensures a connection is active if credentials exist.
  /// Used for "Auto-Wake" from deep sleep or idle timeouts.
  Future<bool> ensureConnected() async {
    if (_status == ConnectionStatus.connected) return true;
    if (!hasValidCredentials) return false;

    _logger.info('ensureConnected: Triggering background auto-wake...');

    return connect();
  }

  void sendAudioChunk(Uint8List data) {
    if (_pendingConfigChange) {
      // A config/identity change is being applied. Keep fresh audio local
      // until the replacement connection is ready rather than leaking it
      // onto the stale socket during shutdown.
      _audioBuffer.add(data);

      return;
    }

    final activeChannel = _channel;
    if (_handshake.canSendAudio() && activeChannel != null) {
      activeChannel.sink.add(data);
      _heartbeat.reset(onTimeout: () => disconnect(reason: 'Idle'));
    } else if (_handshake.state == HandshakeState.authenticating ||
        _isConnecting) {
      // Buffer chunks while connecting or authenticating to prevent audio loss
      _audioBuffer.add(data);
    }
  }

  void sendEndSignal() => _sendJson({'event': 'end-of-stream'});
  void sendLog(String level, String msg) =>
      _sendJson({'event': 'log', 'level': level, 'message': msg});

  /// Simulates a server-initiated close without a real socket.
  /// Use only in tests annotated with @visibleForTesting.
  @visibleForTesting
  void processCloseForTesting(int? code, String? reason) =>
      _processClose(code, reason);

  /// Forces the service into a connected state without a real socket.
  /// Lets tests exercise disconnect/reconnect logic in isolation.
  @visibleForTesting
  void forceConnectedForTesting() {
    _status = ConnectionStatus.connected;
    _isAuthenticatedSession = true;
    _isIntentionalDisconnect = false;
  }

  /// Exercises the _handleRawMessage authenticated branch without a real socket.
  /// Advances through the authenticating state first so the state machine does
  /// not log a spurious invalid-transition warning in test output.
  @visibleForTesting
  void receiveAuthenticatedForTesting() {
    _handshake.transitionTo(HandshakeState.authenticating);
    _handleRawMessage('{"event":"authenticated"}');
  }

  /// Seeds the audio buffer with a test chunk to exercise the flush/clear paths.
  @visibleForTesting
  void bufferAudioForTesting(Uint8List chunk) => _audioBuffer.add(chunk);

  // --- Internal Logic ---

  Future<void> _sendClientHello() async {
    final String? token = _authService.isAuthenticated
        ? await _authService.getAccessToken()
        : _activeApiKey;
    final String authType = _authService.isAuthenticated ? 'oidc' : 'api_key';

    if (token == null) throw Exception('Auth token missing');

    final payload = await _payloadBuilder.buildHello(
      token: token,
      authType: authType,
      incognito: _settingsService.incognitoMode,
    );

    _sendJson(payload);
    _handshake.transitionTo(HandshakeState.authenticating);
  }

  void _handleRawMessage(Object? data) {
    _heartbeat.reset(onTimeout: () => disconnect(reason: 'Idle'));
    if (data is! String) return;

    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final event = json['event'];

      if (event == 'authenticated') {
        _isAuthenticatedSession = true;
        _handshake.transitionTo(HandshakeState.authenticated);
        _updateStatus(ConnectionStatus.connected);
        _logger.info('Handshake success | CID: $_connectionId');
        if (_pendingConfigChange) {
          // A config/identity change arrived mid-handshake. Discard buffered
          // audio — it must not be sent on a session whose URI, credentials, or
          // incognito flag are already stale. The buffer will refill after the
          // reconnect completes with fresh settings.
          _audioBuffer.clear();
          unawaited(
            disconnect(reason: 'Configuration/Identity update required'),
          );
        } else {
          // Happy path: flush any audio that was buffered during the handshake.
          // _channel is non-null here by construction — it is assigned in
          // connect() before the stream listener that delivers this event is
          // attached — but the guard makes that ordering invariant explicit.
          final ch = _channel;
          if (ch != null) _audioBuffer.flush(ch);
        }
      } else if (event == 'error' &&
          (json['code'] == _authForbiddenCode ||
              json['code'] == _policyViolationCode ||
              json['message']?.contains('Auth') == true)) {
        _handleAuthError(json['message']);
      } else {
        _messageController.add(json);
      }
    } catch (e) {
      _logger.error('Message parse error', error: e);
    }
  }

  void _handleAuthError(Object? message) {
    final msgStr = message?.toString() ?? 'Auth failed';
    final lowerMsg = msgStr.toLowerCase();
    _lastHandshakeError = msgStr;
    _handshake.transitionTo(HandshakeState.failed);

    if (lowerMsg.contains('ban') || lowerMsg.contains('cooldown')) {
      _banState.parseBanMessage(msgStr);
      _updateStatus(ConnectionStatus.banned);
    }

    _isIntentionalDisconnect = true;
    _handleDisconnect();
  }

  void _handleSocketError(Object? error) {
    _logger.error('WebSocket transport error', error: error);
    _handleDisconnect();
  }

  void _handleSocketClose() {
    final code = _channel?.closeCode;
    final reason = _channel?.closeReason;
    _logger.info(
      'WebSocket closed | Code: ${code ?? "none"} | Reason: ${reason ?? "none"}',
    );
    _processClose(code, reason);
  }

  void _processClose(int? code, String? reason) {
    if (code == _serverIdleCloseCode) {
      // Server evicted an idle authenticated session with no audio activity.
      // Go quietly idle — reconnecting would only produce an immediate re-eviction loop.
      _logger.info(
        'Server closed idle session | Code: 4001 | Reason: ${reason ?? "No audio activity"}',
      );
      _isIntentionalDisconnect = true;
      _handleDisconnect();

      return;
    }

    if (code == _policyViolationCode) {
      if (_lastHandshakeError == null) {
        _logger.warning(
          'Server rejected connection | Code: 1008 | Reason: ${reason ?? "Policy violation"}',
        );
        _handleAuthError(reason);
      } else {
        _handleDisconnect();
      }

      return;
    }
    _handleDisconnect();
  }

  void _handleDisconnect() {
    final bool wasActive = _status == ConnectionStatus.connected;
    if (_status != ConnectionStatus.banned) {
      _updateStatus(ConnectionStatus.disconnected);
    }

    _isAuthenticatedSession = false;
    _channel = null;
    _connectionId = null;
    _heartbeat.stop();
    _isConnecting = false;
    // Preserve the failed state so UI can display auth error messaging.
    // connect() resets it at the start of the next attempt.
    if (_handshake.state != HandshakeState.failed) {
      _handshake.reset();
    }

    final bool configPending = _pendingConfigChange;
    _pendingConfigChange = false;

    if (configPending && !_banState.isBanned) {
      _logger.info(
        'Reconnecting immediately | Reason: configuration or identity update',
      );
      // Config/identity changed mid-session: reconnect immediately with fresh
      // settings. Bypassing ReconnectionManager's backoff timer avoids a gap
      // where connect() has already returned true but the socket is gone and
      // live audio can neither be sent nor buffered.
      //
      // If the immediate attempt fails (e.g. bad new credentials, unreachable
      // URI), fall back to the normal backoff timer so the app does not go
      // silently idle with no recovery path.
      unawaited(_attemptImmediateReconnect());
    } else if (!_isIntentionalDisconnect && wasActive && !_banState.isBanned) {
      _logger.warning(
        'Unexpected disconnect while active | Scheduling reconnect with backoff',
      );
      // Genuine unexpected drop: use the backoff timer so we don't hammer the
      // server after a transient network failure.
      _reconnection.schedule(
        onRetry: () => connect(),
        lastError: _lastHandshakeError,
        isBanned: _banState.isBanned,
      );
    }
  }

  Future<void> _attemptImmediateReconnect() async {
    final success = await connect();
    if (!success && !_banState.isBanned) {
      _reconnection.schedule(
        onRetry: () => connect(),
        lastError: _lastHandshakeError,
        isBanned: _banState.isBanned,
      );
    }
  }

  void _sendJson(Map<String, dynamic> json) {
    final ch = _channel;
    if (ch != null) {
      ch.sink.add(jsonEncode(json));
      _heartbeat.reset(onTimeout: () => disconnect(reason: 'Idle'));
    }
  }

  Future<Map<String, dynamic>?> _waitForServerHello() async {
    final completer = Completer<Map<String, dynamic>?>();
    final sub = onMessage.listen((msg) {
      if (msg['event'] == 'hello' && !completer.isCompleted) {
        completer.complete(msg);
      }
    });

    try {
      final val = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          return null;
        },
      );

      if (val != null) {
        _backendMinVersion = val['min_version']?.toString();
        _backendSecVersion = val['sec_version']?.toString();
        _backendServerVersion = val['version']?.toString();
        _connectionId = val['cid']?.toString();
        notifyListeners(); // Signal that version requirements are now available
      }

      return val;
    } finally {
      unawaited(sub.cancel());
    }
  }

  void _updateStatus(ConnectionStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      _statusController.add(newStatus);
      notifyListeners();
    }
  }
}

enum ConnectionStatus { disconnected, connecting, connected, banned }
