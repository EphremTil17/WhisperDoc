import 'dart:async';
import 'dart:convert';
import 'dart:io' show WebSocket;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
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
import 'server_problem.dart';

/// Opens a socket to an already validated, normalized server address.
typedef ChannelOpener = Future<WebSocketChannel> Function(String uri);

/// Lean orchestrator for WebSocket connectivity.
/// Delegates specialized logic to sub-managers for buffering, reconnection, and heartbeats.
class WebSocketService extends ChangeNotifier {
  static const int _normalCloseCode = 1000;
  static const int _policyViolationCode = 1008;
  static const int _serverIdleCloseCode = 4001;
  static const Duration _pingInterval = Duration(seconds: 30);
  static const Duration _helloTimeout = Duration(seconds: 5);

  /// Backend `error_code`s that end the session. Everything else (NO_AUDIO,
  /// TRANSCRIPTION_FAILED, ...) is operational and goes to [onMessage].
  static const Set<String> _sessionErrorCodes = {
    'AUTH_FAILED',
    'IP_BANNED',
    'VERSION_OUTDATED',
    'MAX_CONNECTIONS',
    'HANDSHAKE_REQUIRED',
    'MALFORMED_JSON',
    'INVALID_EVENT',
    'DUPLICATE_HANDSHAKE',
  };

  final SettingsService _settingsService;
  final AuthService _authService;
  final ChannelOpener _openChannel;

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
  bool _isIntentionalDisconnect = false;
  bool _pendingConfigChange = false;
  bool _endSignalPending = false;
  bool _disposed = false;
  int _connectGeneration = 0;
  Future<bool>? _attempt;
  Completer<bool>? _authWaiter;
  String? _lastHandshakeError;
  ServerProblem _serverProblem = ServerProblem.none;
  String? _activeApiKey;
  SecurityStatus _securityStatus = SecurityStatus.secure; // Default to secure
  String? _backendMinVersion;
  String? _backendSecVersion;
  String? _backendServerVersion;
  String? _connectionId;

  // State Getters
  ConnectionStatus get status => _status;
  String? get lastHandshakeError => _lastHandshakeError;

  /// Kept through later attempts, so a retry doesn't flash "ready" before it
  /// fails again. Cleared once a server says hello.
  ServerProblem get serverProblem => _serverProblem;

  /// The configured server's host, for asking whether to trust it.
  String get serverHost =>
      Uri.tryParse(_transportSecurity.normalizeUri(_settingsService.serverUri))
          ?.host ??
      _settingsService.serverUri;
  SecurityStatus get securityStatus => _securityStatus;
  BanStateService get banState => _banState;
  HandshakeStateMachine get handshakeState => _handshake;
  String? get backendMinVersion => _backendMinVersion;
  String? get backendSecVersion => _backendSecVersion;
  String? get backendServerVersion => _backendServerVersion;
  Stream<ConnectionStatus> get onStatusChanged => _statusController.stream;
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;
  bool get hasValidCredentials =>
      _authService.isAuthenticated ||
      (_settingsService.cachedApiKey?.isNotEmpty ?? false);

  /// Server mode with credentials: a dropped or unreachable connection is
  /// worth retrying. Groq mode, sign-out and bans end every retry.
  bool get _wantsConnection =>
      !_settingsService.isGroqMode &&
      hasValidCredentials &&
      !_banState.isBanned;

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

  WebSocketService(
    this._settingsService,
    this._authService, {
    ChannelOpener? openChannel,
  }) : _openChannel = openChannel ?? _openSocket,
       _config = ConfigurationManager(_authService, _settingsService) {
    // Wire up configuration changes
    _config.startObserving(
      onReconnectNeeded: () {
        if (_status == ConnectionStatus.connected ||
            _status == ConnectionStatus.connecting) {
          // Apply the new config once this connection is gone: reconnect at
          // once if it is still wanted (not in Groq mode, still signed in).
          _pendingConfigChange = true;
        }
        if (_status == ConnectionStatus.connected) {
          unawaited(
            disconnect(reason: 'Configuration/Identity update required'),
          );
        } else {
          // New settings: retries start over against the new target.
          _reconnection.reset();
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
      if (state != HandshakeState.failed) return;
      _audioBuffer.clear();
      // A handshake that timed out leaves its socket open: close it. Checked
      // on delivery, so a newer attempt that already reset the state is safe.
      if (_handshake.state == HandshakeState.failed && _channel != null) {
        _lastHandshakeError ??= 'The server did not confirm the sign-in';
        _isIntentionalDisconnect = true;
        _handleDisconnect();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _heartbeat.stop();
    _reconnection.stop();
    _config.stopObserving();
    _dropChannel();
    _handshake.dispose();
    _banState.dispose();
    unawaited(_statusController.close());
    unawaited(_messageController.close());
    super.dispose();
  }

  @override
  void notifyListeners() {
    // A connect attempt can settle after dispose.
    if (!_disposed) super.notifyListeners();
  }

  // --- External API ---

  /// Connects and completes the sign-in handshake. True once the server has
  /// accepted the sign-in; false on any failure. Calls while an attempt is
  /// in flight share it rather than opening a second socket.
  Future<bool> connect({String? uriOverride, String? apiKeyOverride}) {
    final overridden = uriOverride != null || apiKeyOverride != null;
    if (_status == ConnectionStatus.connected && !overridden) {
      return Future.value(true);
    }
    if (_banState.isBanned || _disposed) return Future.value(false);

    final inFlight = _attempt;
    if (inFlight != null) return inFlight;

    final attempt = _connect(uriOverride, apiKeyOverride);
    _attempt = attempt;
    unawaited(
      attempt.whenComplete(() {
        if (identical(_attempt, attempt)) _attempt = null;
      }),
    );

    return attempt;
  }

  /// Remembers the configured server as safe for the user's sign-in, then
  /// connects to it.
  Future<bool> trustServerAndConnect() async {
    final origin = _transportSecurity.serverOrigin(_settingsService.serverUri);
    if (origin == null) return false;
    await _settingsService.trustServer(origin);

    return connect();
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

  /// Tells the server the dictation is over. Sent now on a live session, or
  /// after the buffered audio once a handshake in flight completes. False
  /// when there is no session to send it on: the dictation is lost.
  bool sendEndSignal() {
    if (_handshake.canSendAudio() && _channel != null) {
      _sendJson({'event': 'end-of-stream'});

      return true;
    }
    if (_isConnecting) {
      _endSignalPending = true;

      return true;
    }

    return false;
  }

  /// Simulates a server-initiated close without a real socket.
  @visibleForTesting
  void processCloseForTesting(int? code, String? reason) =>
      _processClose(code, reason);

  /// Forces the service into a connected state without a real socket.
  /// Lets tests exercise disconnect/reconnect logic in isolation.
  @visibleForTesting
  void forceConnectedForTesting() {
    _status = ConnectionStatus.connected;
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

  /// Feeds a raw server frame through the message router.
  @visibleForTesting
  void handleRawMessageForTesting(Object? data) => _handleRawMessage(data);

  /// Seeds the audio buffer with a test chunk to exercise the flush/clear paths.
  @visibleForTesting
  void bufferAudioForTesting(Uint8List chunk) => _audioBuffer.add(chunk);

  // --- Internal Logic ---

  /// Opens the socket manually so pingInterval can be set: dart:io then sends
  /// protocol-level pings, as Python's websockets library does by default, so
  /// this client stays connected as long as the terminal client does under
  /// the same tunnel.
  static Future<WebSocketChannel> _openSocket(String uri) async {
    final pending = WebSocket.connect(uri);
    try {
      final socket = await pending.timeout(AppConstants.wsConnectTimeout);
      socket.pingInterval = _pingInterval;

      return IOWebSocketChannel(socket);
    } on TimeoutException {
      unawaited(_closeLateSocket(pending));
      rethrow;
    }
  }

  /// A socket that opens after we gave up must not linger.
  static Future<void> _closeLateSocket(Future<WebSocket> pending) async {
    try {
      final socket = await pending;
      await socket.close();
    } on Object catch (e) {
      LoggingService().info('Abandoned socket never opened: $e');
    }
  }

  Future<bool> _connect(String? uriOverride, String? apiKeyOverride) async {
    // Any disconnect ends this attempt; after one, it must not touch the
    // state its replacement now owns.
    final generation = ++_connectGeneration;

    _isConnecting = true;
    _isIntentionalDisconnect = false;
    _lastHandshakeError = null;
    _updateStatus(ConnectionStatus.connecting);
    notifyListeners();
    _handshake.reset();
    var problem = ServerProblem.unreachable;

    try {
      final uriString = uriOverride ?? _settingsService.serverUri;
      _activeApiKey = apiKeyOverride ?? _settingsService.cachedApiKey;
      final hasApiKey = _activeApiKey?.isNotEmpty ?? false;

      if (!_authService.isAuthenticated && !hasApiKey) {
        _lastHandshakeError = 'Authentication required';
        _handshake.transitionTo(HandshakeState.failed);
        throw Exception('No authentication available');
      }

      final security = await _transportSecurity.validateServerUri(uriString);
      if (generation != _connectGeneration) return false;
      _securityStatus = security;
      if (security == SecurityStatus.blocked) {
        problem = ServerProblem.insecure;
        throw Exception('Security violation');
      }

      // The sign-in token lets whoever receives it act as the user, so it
      // goes only to a server the user agreed to. An API key was issued by
      // the server it is set for, so it needs no such check.
      final useSignIn =
          _authService.isAuthenticated && _isTrustedForSignIn(uriString);
      if (!useSignIn && !hasApiKey) {
        problem = ServerProblem.untrusted;
        throw Exception('Server not trusted with the sign-in');
      }

      _logger.info(
        'Connecting to: $uriString (Auth: ${useSignIn ? "OIDC" : "API_KEY"})',
      );
      final ch = await _openChannel(_transportSecurity.normalizeUri(uriString));
      if (generation != _connectGeneration || _disposed) {
        ch.sink.close(_normalCloseCode).ignore();

        return false;
      }
      _channel = ch;

      // Each socket reports only while it is the current one: a stale socket
      // closing late must not tear down its replacement.
      ch.stream.listen(
        (data) {
          if (identical(ch, _channel)) _handleRawMessage(data);
        },
        onError: (Object error) {
          if (identical(ch, _channel)) _handleSocketError(error);
        },
        onDone: () {
          if (identical(ch, _channel)) _handleSocketClose();
        },
      );

      final hello = await _waitForServerHello();
      if (generation != _connectGeneration) return false;
      if (hello == null) throw Exception('Handshake timeout');

      final accepted = Completer<bool>();
      _authWaiter = accepted;
      await _sendClientHello(useSignIn: useSignIn);
      if (generation != _connectGeneration) return false;

      // Settled by the 'authenticated' event, or false by any disconnect
      // (rejection, timeout, dropped socket).
      return await accepted.future;
    } catch (e) {
      _logger.error('Connection failed', error: e);
      if (generation != _connectGeneration) return false;
      if (e is _MissingAuthTokenException) {
        _lastHandshakeError = 'Identity session expired or missing';
        _handshake.transitionTo(HandshakeState.failed);
      }
      // A failed handshake is a credential problem, not a missing server.
      final serverAtFault = _handshake.state != HandshakeState.failed;
      if (serverAtFault) _serverProblem = problem;
      _handleDisconnect(); // consumes _pendingConfigChange for the failure path
      if (serverAtFault && problem == ServerProblem.unreachable) {
        _scheduleRetry();
      }

      return false;
    }
  }

  /// The built-in server, or one the user agreed to send their sign-in to.
  bool _isTrustedForSignIn(String uriString) {
    final origin = _transportSecurity.serverOrigin(uriString);
    if (origin == null) return false;

    return origin ==
            _transportSecurity.serverOrigin(AppConstants.defaultServerUri) ||
        _settingsService.isTrustedServer(origin);
  }

  Future<void> _sendClientHello({required bool useSignIn}) async {
    final String? token = useSignIn
        ? await _authService.getAccessToken()
        : _activeApiKey;

    if (token == null || token.isEmpty) {
      throw const _MissingAuthTokenException();
    }

    final payload = await _payloadBuilder.buildHello(
      token: token,
      authType: useSignIn ? 'oidc' : 'api_key',
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
        _handshake.transitionTo(HandshakeState.authenticated);
        _isConnecting = false;
        _reconnection.reset();
        _updateStatus(ConnectionStatus.connected);
        _logger.info('Handshake success | CID: $_connectionId');
        if (_pendingConfigChange) {
          // A config/identity change arrived mid-handshake. Discard buffered
          // audio — it must not be sent on a session whose URI, credentials, or
          // incognito flag are already stale. The buffer will refill after the
          // reconnect completes with fresh settings.
          _audioBuffer.clear();
          _endSignalPending = false;
          unawaited(
            disconnect(reason: 'Configuration/Identity update required'),
          );
        } else {
          // Happy path: flush any audio that was buffered during the handshake,
          // then end the dictation if it finished while connecting.
          final ch = _channel;
          if (ch != null) _audioBuffer.flush(ch);
          if (_endSignalPending) {
            _endSignalPending = false;
            _sendJson({'event': 'end-of-stream'});
          }
        }
        _settleAuth(accepted: true);
      } else if (event == 'error' &&
          _sessionErrorCodes.contains(json['error_code'])) {
        _handleAuthError(
          json['message'],
          errorCode: json['error_code'] as String,
        );
      } else {
        _messageController.add(json);
      }
    } catch (e) {
      _logger.error('Message parse error', error: e);
    }
  }

  /// Ends the session after a session-level rejection. [errorCode] comes from
  /// the server's error JSON; it is null on the close-frame fallback path,
  /// where only the close reason text is available.
  void _handleAuthError(Object? message, {String? errorCode}) {
    final msgStr = message?.toString() ?? 'Auth failed';
    final lowerMsg = msgStr.toLowerCase();
    _lastHandshakeError = msgStr;
    _handshake.transitionTo(HandshakeState.failed);

    final isBan = errorCode != null
        ? errorCode == 'IP_BANNED'
        : lowerMsg.contains('ban') || lowerMsg.contains('cooldown');
    if (isBan) {
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

    _dropChannel();
    _connectionId = null;
    _heartbeat.stop();
    _isConnecting = false;
    _attempt = null;
    _connectGeneration++;
    _endSignalPending = false;
    _settleAuth(accepted: false);
    // Preserve the failed state so UI can display auth error messaging.
    // connect() resets it at the start of the next attempt.
    if (_handshake.state != HandshakeState.failed) {
      _handshake.reset();
    }

    final bool configPending = _pendingConfigChange;
    _pendingConfigChange = false;

    if (configPending && _wantsConnection) {
      _logger.info(
        'Reconnecting immediately | Reason: configuration or identity update',
      );
      // Config/identity changed mid-session: reconnect immediately with fresh
      // settings, bypassing the backoff timer. If that attempt fails, the
      // normal backoff takes over so the app does not go silently idle.
      unawaited(_attemptImmediateReconnect());
    } else if (!_isIntentionalDisconnect && wasActive) {
      _logger.warning(
        'Unexpected disconnect while active | Scheduling reconnect with backoff',
      );
      _scheduleRetry();
    }
  }

  /// Forgets the current socket and closes it, so nothing it says later is
  /// heard and the server sees the session end.
  void _dropChannel() {
    final ch = _channel;
    _channel = null;
    ch?.sink.close(_normalCloseCode).ignore();
  }

  void _settleAuth({required bool accepted}) {
    final waiter = _authWaiter;
    _authWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete(accepted);
  }

  Future<void> _attemptImmediateReconnect() async {
    final success = await connect();
    if (!success) _scheduleRetry();
  }

  void _scheduleRetry() {
    if (!_wantsConnection || _disposed) return;
    _reconnection.schedule(
      onRetry: _retry,
      lastError: _lastHandshakeError,
      isBanned: _banState.isBanned,
    );
  }

  Future<void> _retry() async {
    // Settings may have changed while the timer ran.
    if (_wantsConnection && _status == ConnectionStatus.disconnected) {
      await connect();
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
        _helloTimeout,
        onTimeout: () => null,
      );

      if (val != null) {
        _backendMinVersion = val['min_version']?.toString();
        _backendSecVersion = val['sec_version']?.toString();
        _backendServerVersion = val['version']?.toString();
        _connectionId = val['cid']?.toString();
        _serverProblem = ServerProblem.none;
        notifyListeners(); // Signal that version requirements are now available
      }

      return val;
    } finally {
      unawaited(sub.cancel());
    }
  }

  void _updateStatus(ConnectionStatus newStatus) {
    if (_status != newStatus && !_disposed) {
      _status = newStatus;
      _statusController.add(newStatus);
      notifyListeners();
    }
  }
}

enum ConnectionStatus { disconnected, connecting, connected, banned }

/// No credential was available for the handshake (expired/missing OIDC
/// session or no API key). Raised before anything is sent to the server.
class _MissingAuthTokenException implements Exception {
  const _MissingAuthTokenException();

  @override
  String toString() => 'Auth token missing';
}
