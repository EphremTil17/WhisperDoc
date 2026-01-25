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
import 'package:flutter_client/core/constants/app_constants.dart';
import 'websocket/handshake_payload_builder.dart';

enum ConnectionStatus { disconnected, connecting, connected, banned }

/// Hardened WebSocket service with integrated security layers.
///
/// Security Features:
/// - Transport Security: WSS enforcement with RFC 1918 validation
/// - Handshake Protocol: Authentication before data transmission
/// - Ban Awareness: 1008 close code handling with cooldown
/// - Audio Buffering: Queue data during handshake, flush after auth
///
/// Matches backend v2.8.x security architecture and Python terminal client patterns.
class WebSocketService extends ChangeNotifier {
  final SettingsService _settingsService;
  final TransportSecurityService _transportSecurity =
      TransportSecurityService();
  final HandshakeStateMachine _handshake = HandshakeStateMachine();
  final BanStateService _banState = BanStateService();
  final AuthService _authService;
  final HandshakePayloadBuilder _payloadBuilder = HandshakePayloadBuilder();

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
  bool get isConnecting => _isConnecting;
  Stream<ConnectionStatus> get onStatusChanged => _statusController.stream;
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;

  String? _lastHandshakeError;
  String? get lastHandshakeError => _lastHandshakeError;

  // Expose ban state for UI
  BanStateService get banState => _banState;
  HandshakeStateMachine get handshakeState => _handshake;

  Timer? _reconnectTimer;
  Timer? _idleTimer;
  bool _isIntentionalDisconnect = false;
  bool _isConnecting = false;
  bool _isAuthenticatedSession = false;
  bool get isAuthenticatedSession => _isAuthenticatedSession;

  // Audio buffer with 5s limit (16kHz * 16-bit * 1ch * 5s = ~160KB)
  final List<Uint8List> _pendingAudioBuffer = [];
  static const int _maxBufferSize = 160000; // bytes
  int _currentBufferSize = 0;
  String? _activeApiKey;

  static const Duration idleTimeout = AppConstants.wsIdleTimeout;
  String _lastKnownUri;
  String? _lastKnownApiKey;
  bool _lastKnownIncognito = false;

  WebSocketService(this._settingsService, this._authService)
    : _lastKnownUri = _settingsService.serverUri,
      _lastKnownApiKey = _settingsService.cachedApiKey,
      _lastKnownIncognito = _settingsService.incognitoMode {
    _settingsService.addListener(_onSettingsChanged);
    _authService.addListener(_onAuthChanged);
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
    _authService.removeListener(_onAuthChanged);
    _handshake.dispose();
    _banState.dispose();
    unawaited(_statusController.close());
    unawaited(_messageController.close());
    super.dispose();
  }

  void _onAuthChanged() async {
    _logger.info('Auth state changed, resetting session if connected');
    if (_status == ConnectionStatus.connected ||
        _status == ConnectionStatus.connecting) {
      await disconnect(reason: 'Identity change');
    }

    // Reset session auth flag if signed out
    if (!_authService.isAuthenticated) {
      _isAuthenticatedSession = false;
    }

    // Auto-connect if newly authenticated
    if (_authService.isAuthenticated && _status == ConnectionStatus.disconnected) {
      _logger.info('Automatically connecting after successful authentication');
      unawaited(connect());
    }
    notifyListeners();
  }

  void _onSettingsChanged() async {
    final currentUri = _settingsService.serverUri;
    final currentIncognito = _settingsService.incognitoMode;
    final currentApiKey = await _settingsService.getApiKey();

    bool credentialsChanged = false;

    // 1. URI Change
    if (currentUri != _lastKnownUri) {
      _logger.info('Server URI changed: $_lastKnownUri -> $currentUri');
      _lastKnownUri = currentUri;
      credentialsChanged = true;
    }

    // 2. API Key Change
    if (currentApiKey != _lastKnownApiKey) {
      _logger.info('API Key changed, resetting session auth');
      _lastKnownApiKey = currentApiKey;
      credentialsChanged = true;
    }

    if (credentialsChanged) {
      _isAuthenticatedSession = false;
      if (_status == ConnectionStatus.connected ||
          _status == ConnectionStatus.connecting) {
        await disconnect(reason: 'Credentials changed');
      }

      // Auto-connect if valid credentials available
      if (currentApiKey != null && currentApiKey.isNotEmpty && _status == ConnectionStatus.disconnected) {
        _logger.info('Automatically connecting after credentials update');
        unawaited(connect());
      }
      notifyListeners();
      return;
    }

    // 3. Incognito mode change (Session remains authorized)
    if (currentIncognito != _lastKnownIncognito) {
      _lastKnownIncognito = currentIncognito;
      if (_status == ConnectionStatus.connected) {
        _logger.info(
          'Incognito mode changed, reconnecting with new privacy flag (Session Auth maintained)',
        );
        await disconnect(reason: 'Incognito mode toggle');
      }
    }
  }

  Future<bool> connect({String? uriOverride, String? apiKeyOverride}) async {
    if (_status == ConnectionStatus.connected &&
        uriOverride == null &&
        apiKeyOverride == null) {
      return true;
    }
    if (_isConnecting) return false;
    if (_banState.isBanned) {
      _logger.warning(
        'Cannot connect: IP is banned for ${_banState.cooldownRemaining}s',
      );
      return false;
    }

    _isConnecting = true;
    _isIntentionalDisconnect = false;
    _lastHandshakeError = null;
    _updateStatus(ConnectionStatus.connecting);
    _handshake.reset();

    try {
      final uriString = uriOverride ?? _settingsService.serverUri;
      _activeApiKey = apiKeyOverride ?? await _settingsService.getApiKey();

      // 0. Pre-flight Auth Check: Don't even open the socket if we have no way to authenticate
      if (!_authService.isAuthenticated &&
          (_activeApiKey == null || _activeApiKey!.isEmpty)) {
        _logger.error(
          'Connection aborted: No OIDC session or API Key available',
        );
        _isConnecting = false;
        _handleDisconnect();
        return false;
      }

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
    String? token;
    String authType = 'api_key';

    // 1. Prioritize OIDC Identity Token
    if (_authService.isAuthenticated) {
      token = await _authService.getAccessToken();
      if (token != null && token.isNotEmpty) {
        authType = 'oidc';
        _logger.info('Forwarding OIDC identity token for handshake');
      }
    }

    // 2. Fallback to API Key only if OIDC is not being used
    if (token == null || token.isEmpty) {
      token = _activeApiKey;
      if (token != null && token.isNotEmpty) {
        authType = 'api_key';
        _logger.info('Forwarding static API key for handshake');
      }
    }

    if (token == null || token.isEmpty) {
      throw Exception('No authentication token available');
    }

    final payload = await _payloadBuilder.buildHello(
      token: token,
      authType: authType,
      incognito: _settingsService.incognitoMode,
    );

    _logger.info(
      'Sending client hello (auth: $authType, incognito: ${payload['incognito']})',
    );
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
            _isAuthenticatedSession = true;
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
              _lastHandshakeError =
                  message?.toString() ?? 'Authentication failed';
              _isAuthenticatedSession = false;
              _handshake.transitionTo(HandshakeState.failed);
              _isIntentionalDisconnect =
                  true; // Stop auto-reconnect on auth failure
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
        _lastHandshakeError = closeReason ?? 'Authentication refused by server';
        _handshake.transitionTo(HandshakeState.failed);
        _updateStatus(ConnectionStatus.disconnected);

        // Notify of auth failure
        _messageController.add({
          'event': 'error',
          'code': 'AUTH_FAILED',
          'message': _lastHandshakeError,
        });
      }

      _isIntentionalDisconnect = true; // Disable auto-reconnect on 1008
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

    // Only reset handshake to locked if it's not in a terminal error state
    // (failed or banned). This ensures the UI remembers the failure.
    if (_handshake.state != HandshakeState.failed &&
        _handshake.state != HandshakeState.banned) {
      _handshake.reset();
    }

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
      // Avoid spamming logs if we already know why it's failing
      if (_handshake.state != HandshakeState.failed &&
          _handshake.state != HandshakeState.banned) {
        _logger.warning('Cannot send audio in ${_handshake.state.name} state');
      }
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

  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive ?? false) return;
    if (_banState.isBanned) return;

    // KILL SWITCH: If the last disconnect was due to a missing/invalid credential,
    // do NOT auto-reconnect. Hammering correctly results in backend bans.
    if (_lastHandshakeError != null) {
      final err = _lastHandshakeError!.toLowerCase();
      if (err.contains('no oidc session') || 
          err.contains('authentication token') ||
          err.contains('access denied') ||
          err.contains('authentication failed') ||
          err.contains('invalid credentials')) {
        _logger.warning('Auto-reconnect aborted: Authentication failure ($err). Please sign in manually.');
        return;
      }
    }

    const delaySeconds = 5;
    _logger.info(
      'Reconnect scheduled in ${delaySeconds}s (Attempt ${_reconnectAttempts + 1})',
    );

    _reconnectTimer = Timer(const Duration(seconds: delaySeconds), () {
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
