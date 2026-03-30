// ignore_for_file: avoid-dynamic, no-empty-block
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/services/utility/settings_service.dart';
import 'package:flutter_client/services/auth/auth_service.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/transport/handshake_state_machine.dart';
import 'package:flutter_client/services/transport/configuration_manager.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ---------------------------------------------------------------------------
// Test constants
// ---------------------------------------------------------------------------

abstract final class _WebSocketServiceTest {
  static const int identityChangeCount = 2;
  static const int signOutReconnectCount = 3;
  static const int idleEvictionCloseCode = 4001;
  static const int unauthorizedCloseCode = 1008;
}

// ---------------------------------------------------------------------------
// Minimal stubs — only implement what ConfigurationManager / WebSocketService
// constructor calls. Everything else throws UnimplementedError at runtime.
// ---------------------------------------------------------------------------

class _StubAuthService extends ChangeNotifier implements AuthService {
  bool _isAuthenticated = false;
  String? _userId;

  @override
  bool get isAuthenticated => _isAuthenticated;

  @override
  String? get idToken => _isAuthenticated ? 'stub_token' : null;

  @override
  bool get isAuthenticating => false;

  @override
  Map<String, dynamic>? get currentUser =>
      _isAuthenticated && _userId != null ? {'id': _userId} : null;

  void setAuthenticated(bool value, {String? userId}) {
    _isAuthenticated = value;
    _userId = value ? userId : null;
    notifyListeners();
  }

  // Remaining AuthService members are not exercised by these tests.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubSettingsService extends ChangeNotifier implements SettingsService {
  // Fields
  String _serverUri;
  final String? _apiKey;

  // Getters — must precede constructors per DCM member-ordering
  @override
  String get serverUri => _serverUri;

  @override
  String? get cachedApiKey => _apiKey;

  @override
  bool get incognitoMode => false;

  @override
  String get transcriptionMode => 'backend';

  @override
  bool get isGroqMode => false;

  // Constructor
  _StubSettingsService({String serverUri = 'ws://localhost', String? apiKey})
    : _serverUri = serverUri,
      _apiKey = apiKey;

  // Methods
  @override
  Future<String?> getApiKey() async => _apiKey;

  void changeUri(String newUri) {
    _serverUri = newUri;
    notifyListeners();
  }

  // Remaining SettingsService members are not exercised by these tests.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWebSocketChannel
    with StreamChannelMixin
    implements WebSocketChannel {
  final List<dynamic> sent = [];
  final StreamController<dynamic> _controller =
      StreamController<dynamic>.broadcast();

  int? _closeCode;
  String? _closeReason;

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  WebSocketSink get sink => _FakeWebSocketSink(
    onAdd: sent.add,
    onClose: (code, reason) async {
      _closeCode = code;
      _closeReason = reason;
      await _controller.close();
    },
  );

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => _closeReason;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready async {}
}

class _FakeWebSocketSink implements WebSocketSink {
  // Public fields
  final void Function(dynamic data) onAdd;
  final Future<void> Function(int? code, String? reason) onClose;

  // Private fields
  final Completer<void> _done = Completer<void>();

  // Public getters — must precede constructor per DCM member-ordering
  @override
  Future<void> get done => _done.future;

  // Constructor
  _FakeWebSocketSink({required this.onAdd, required this.onClose});

  // Public methods
  @override
  void add(dynamic data) => onAdd(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    await onClose(closeCode, closeReason);
    if (!_done.isCompleted) {
      _done.complete();
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

abstract final class _ServiceFactory {
  static WebSocketService make({String? apiKey}) {
    return WebSocketService(
      _StubSettingsService(apiKey: apiKey),
      _StubAuthService(),
    );
  }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // --- Existing placeholder tests (kept for compatibility) ------------------

  group('WebSocketService Connection States', () {
    test('ConnectionStatus enum has expected values', () {
      expect(ConnectionStatus.values, contains(ConnectionStatus.disconnected));
      expect(ConnectionStatus.values, contains(ConnectionStatus.connecting));
      expect(ConnectionStatus.values, contains(ConnectionStatus.connected));
    });
  });

  // --- OIDC identity fingerprint -------------------------------------------
  //
  // ConfigurationManager._handleAuthChange uses an identity fingerprint to
  // decide when to fire onReconnectNeeded.  It tracks userId (OIDC 'sub')
  // and isAuthenticated.  Silent token refreshes that don't change identity
  // must NOT trigger a reconnect — only actual identity or auth-state
  // changes should.

  group('ConfigurationManager contract', () {
    test(
      'already-authenticated startup seeds fingerprint and skips first benign auth pulse',
      () {
        final auth = _StubAuthService();
        auth.setAuthenticated(true, userId: 'user123');

        final settings = _StubSettingsService();
        final cm = ConfigurationManager(auth, settings);

        int reconnectFires = 0;
        int autoConnectFires = 0;

        cm.startObserving(
          onReconnectNeeded: () => reconnectFires++,
          onAutoConnectDesired: () => autoConnectFires++,
        );

        expect(reconnectFires, 0, reason: 'startup seeding must not reconnect');
        expect(autoConnectFires, 1, reason: 'launch should still auto-connect');

        auth.notifyListeners();
        expect(
          reconnectFires,
          0,
          reason:
              'same authenticated identity should not reconnect on first auth pulse',
        );

        cm.stopObserving();
      },
    );

    test(
      'onReconnectNeeded fires on OIDC identity change, not on every auth pulse',
      () {
        final auth = _StubAuthService();
        final settings = _StubSettingsService();
        final cm = ConfigurationManager(auth, settings);

        int reconnectFires = 0;
        cm.startObserving(
          onReconnectNeeded: () => reconnectFires++,
          onAutoConnectDesired: () {},
        );

        // First sign-in: identity state changes (null → user123)
        auth.setAuthenticated(true, userId: 'user123');
        expect(reconnectFires, 1, reason: 'Identity state changed: sign-in');

        // Silent refresh with same identity: no reconnect
        auth.notifyListeners();
        expect(
          reconnectFires,
          1,
          reason: 'Same identity, should not reconnect',
        );

        // Identity swap (different user): reconnect
        auth.setAuthenticated(true, userId: 'user456');
        expect(
          reconnectFires,
          _WebSocketServiceTest.identityChangeCount,
          reason: 'Identity changed: user123 → user456',
        );

        // Sign-out: auth state changes
        auth.setAuthenticated(false);
        expect(
          reconnectFires,
          _WebSocketServiceTest.signOutReconnectCount,
          reason: 'Sign-out: auth state changed',
        );

        cm.stopObserving();
      },
    );

    // Regression: the original fix narrowed the guard from
    // (connected || connecting) to only (connected), silently dropping config
    // pulses that arrived while a connection was in-flight.
    // The corrected path sets _pendingConfigChange during 'connecting' and
    // consumes it in _handleDisconnect(). This test drives that path directly.
    //
    // Expected lifecycle:
    //   1. _handleDisconnect sees configPending=true → fires connect() immediately.
    //   2. connect() fails (no credentials in this stub) → returns false.
    //   3. The .then fallback arms the backoff timer so the app does not go
    //      silently idle — this is intentional, not a regression.
    test(
      'pending config change fires immediate reconnect then falls back to timer on failure',
      () async {
        final svc =
            _ServiceFactory.make(); // no API key → immediate connect() will fail

        svc.forceConnectedForTesting();
        svc.pendingConfigChangeForTesting = true;
        final statuses = <ConnectionStatus>[];
        svc.onStatusChanged.listen(statuses.add);

        svc.processCloseForTesting(null, null);
        await Future<void>.delayed(Duration.zero);

        // Step 1: immediate connect() was attempted — status hit 'connecting'.
        expect(
          statuses,
          contains(ConnectionStatus.connecting),
          reason:
              'config-driven reconnect must fire connect() immediately, '
              'not wait for the backoff timer',
        );
        // Step 2: connect() failed (no credentials) → fallback timer is now armed.
        expect(
          svc.reconnectionManagerForTesting.isScheduled,
          isTrue,
          reason:
              'when the immediate config-change reconnect fails, the backoff '
              'timer must be armed so the app does not go silently idle',
        );
        // The pending flag must always be consumed exactly once.
        expect(
          svc.pendingConfigChangeForTesting,
          isFalse,
          reason: 'flag must be consumed, not left dangling',
        );

        svc.dispose();
      },
    );
  });

  // --- Regression: close code 4001 must not schedule reconnect -------------
  //
  // When the server evicts an idle authenticated session (close code 4001),
  // the client must go quietly idle. The prior code matched on both code AND
  // a human-readable reason string, which was a brittle contract. The fix uses
  // only the numeric close code 4001.

  group('WebSocketService idle-close handling', () {
    // Regression: close code 4001 (no-audio-activity eviction) must not arm the
    // reconnect timer. The prior implementation matched on a reason string which
    // was brittle; the fix uses only the numeric close code.
    // This test verifies the timer is not scheduled — not just that 'connecting'
    // was not emitted in the instant after the close (a delayed timer would pass
    // that weaker assertion).
    test(
      'close code 4001 leaves service idle with no reconnect timer armed',
      () async {
        final svc = _ServiceFactory.make(apiKey: 'test-key');

        svc.forceConnectedForTesting();
        expect(svc.pendingConfigChangeForTesting, isFalse);

        svc.processCloseForTesting(_WebSocketServiceTest.idleEvictionCloseCode, 'No audio activity');
        await Future<void>.delayed(Duration.zero);

        expect(
          svc.status,
          ConnectionStatus.disconnected,
          reason: 'service must go idle after a 4001 eviction',
        );
        expect(
          svc.reconnectionManagerForTesting.isScheduled,
          isFalse,
          reason:
              '4001 eviction must not arm the reconnect timer — a scheduled '
              'timer would re-evict the client immediately after reconnect',
        );

        svc.dispose();
      },
    );

    test(
      'non-intentional server close (code null) does not loop when already disconnected',
      () async {
        // Guard: a plain unexpected close from a non-connected state must not
        // schedule a reconnect (wasActive=false).
        final svc = _ServiceFactory.make();

        svc.processCloseForTesting(null, null);
        await Future<void>.delayed(Duration.zero);

        expect(svc.status, ConnectionStatus.disconnected);
        svc.dispose();
      },
    );
  });

  // --- Regression: HandshakeState.failed persists through disconnect --------
  //
  // Covered more directly in handshake_state_machine_test.dart.
  // This group verifies the behaviour through the WebSocketService surface.

  group('WebSocketService auth failure state', () {
    test(
      'handshake state is failed after _handleAuthError and before next connect',
      () async {
        final svc = _ServiceFactory.make(apiKey: 'test-key');
        svc.forceConnectedForTesting();

        // Drive _handleAuthError via processCloseForTesting with code 1008 and
        // a non-ban message.  _lastHandshakeError is null at this point, so the
        // 1008 branch calls _handleAuthError(reason).
        svc.processCloseForTesting(_WebSocketServiceTest.unauthorizedCloseCode, 'Unauthorized');

        await Future<void>.delayed(Duration.zero);

        expect(
          svc.handshakeState.state,
          HandshakeState.failed,
          reason:
              'HandshakeState.failed must survive the disconnect so the UI can '
              'show the real error instead of the generic disconnected message',
        );

        svc.dispose();
      },
    );
  });

  // --- Regression: mid-handshake config change must not flush stale audio ---
  //
  // Before the fix, _handshake.stateStream.listen fired flush(_channel!) the
  // moment transitionTo(authenticated) was called — before _handleRawMessage
  // had a chance to check _pendingConfigChange. The fix moves flush inline
  // in _handleRawMessage, gated on !_pendingConfigChange.

  group('WebSocketService mid-handshake config-change ordering', () {
    test(
      'buffered audio is cleared and new audio stays off the stale channel when config changed mid-handshake',
      () async {
        final svc = _ServiceFactory.make(apiKey: 'test-key');
        final channel = _FakeWebSocketChannel();
        svc.channelForTesting = channel;

        final audioBuffer = svc.audioBufferForTesting;
        final sent = channel.sent;

        // Seed the buffer — simulates audio captured while the handshake was
        // in-flight (e.g. user started recording before connection completed).
        svc.bufferAudioForTesting(Uint8List.fromList([1, 2, 3, 4]));
        expect(audioBuffer.isEmpty, isFalse);

        // Simulate a config/identity change that arrived during the handshake.
        svc.pendingConfigChangeForTesting = true;

        // Drive the authenticated event through _handleRawMessage.
        // Without a real socket _channel is null, so if the old code ran
        // flush(_channel!) it would throw a null-check failure here.
        svc.receiveAuthenticatedForTesting();

        expect(
          audioBuffer.isEmpty,
          isTrue,
          reason:
              'buffer must be cleared, not flushed to the stale channel, '
              'when a config change is pending at authentication time',
        );
        expect(
          sent,
          isEmpty,
          reason: 'no buffered audio should be flushed to the stale socket',
        );

        // Fresh chunks arriving during the brief shutdown window must also stay
        // off the stale channel and be held locally for the replacement connect.
        svc.sendAudioChunk(Uint8List.fromList([9, 9]));
        expect(
          sent,
          isEmpty,
          reason:
              'live audio must not slip onto the stale socket during rollover',
        );
        expect(
          audioBuffer.isEmpty,
          isFalse,
          reason:
              'fresh audio should be buffered locally for the reconnect path',
        );

        svc.dispose();
      },
    );

    test(
      'buffered audio is flushed normally when no config change is pending',
      () async {
        final svc = _ServiceFactory.make(apiKey: 'test-key');
        final channel = _FakeWebSocketChannel();
        svc.channelForTesting = channel;

        final audioBuffer = svc.audioBufferForTesting;
        final sent = channel.sent;

        svc.bufferAudioForTesting(Uint8List.fromList([10, 20, 30]));
        expect(audioBuffer.isEmpty, isFalse);

        // No pending config change — authenticated path should flush immediately.
        svc.receiveAuthenticatedForTesting();

        expect(
          audioBuffer.isEmpty,
          isTrue,
          reason:
              'flush() must clear the buffer on the normal authenticated path',
        );
        expect(
          sent,
          hasLength(1),
          reason:
              'happy-path authentication should flush the queued audio chunk',
        );
        expect(sent.single, isA<Uint8List>());

        svc.dispose();
      },
    );
  });
}
