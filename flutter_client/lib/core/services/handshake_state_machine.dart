import 'dart:async';
import 'package:flutter_client/core/services/logging_service.dart';

/// Handshake states for WebSocket connection lifecycle
enum HandshakeState {
  locked, // Initial state, no handshake initiated
  authenticating, // Sent hello, waiting for authenticated response
  authenticated, // Handshake complete, can send audio
  failed, // Authentication failed or timeout
  banned, // IP banned by server (1008 close code)
}

/// Handshake state machine enforcing protocol sequence.
///
/// Implements the security requirement that audio data must NOT be transmitted
/// before receiving the authenticated event from the backend.
///
/// State Transitions:
/// - locked → authenticating: When hello message is sent
/// - authenticating → authenticated: When authenticated event received
/// - authenticating → failed: On auth error or handshake timeout
/// - any → banned: On WebSocket close code 1008
///
/// This prevents the "Protocol Violation" bug where clients send data before
/// completing the authentication handshake.
class HandshakeStateMachine {
  final LoggingService _logger = LoggingService();

  HandshakeState _state = HandshakeState.locked;
  final StreamController<HandshakeState> _stateController =
      StreamController<HandshakeState>.broadcast();

  Timer? _handshakeTimeout;
  static const Duration _timeoutDuration = Duration(
    seconds: 15,
  ); // Matches backend HANDSHAKE_TIMEOUT_SECONDS in security/governance.py

  HandshakeState get state => _state;
  Stream<HandshakeState> get stateStream => _stateController.stream;

  /// Transition to a new state with validation
  void transitionTo(HandshakeState newState) {
    if (_state == newState) return;

    // Validate state transitions
    if (!_isValidTransition(_state, newState)) {
      _logger.warning(
        'Invalid state transition: ${_state.name} → ${newState.name}',
      );
      return;
    }

    _logger.info('Handshake state: ${_state.name} → ${newState.name}');
    _state = newState;
    _stateController.add(newState);

    // Start timeout when entering authenticating state
    if (newState == HandshakeState.authenticating) {
      _startHandshakeTimeout();
    } else {
      _cancelHandshakeTimeout();
    }
  }

  /// Check if audio data can be sent in current state
  bool canSendAudio() {
    return _state == HandshakeState.authenticated;
  }

  /// Reset to locked state (for reconnection)
  void reset() {
    _cancelHandshakeTimeout();
    transitionTo(HandshakeState.locked);
  }

  /// Dispose resources
  void dispose() {
    _cancelHandshakeTimeout();
    unawaited(_stateController.close());
  }

  // --- Private Methods ---

  bool _isValidTransition(HandshakeState from, HandshakeState to) {
    // banned can be reached from any state
    if (to == HandshakeState.banned) return true;

    switch (from) {
      case HandshakeState.locked:
        return to == HandshakeState.authenticating || to == HandshakeState.failed;

      case HandshakeState.authenticating:
        return to == HandshakeState.authenticated ||
            to == HandshakeState.failed;

      case HandshakeState.authenticated:
        // Can only go back to locked on reconnect
        return to == HandshakeState.locked;

      case HandshakeState.failed:
        // Can retry by going back to locked
        return to == HandshakeState.locked;

      case HandshakeState.banned:
        // Can only recover by resetting to locked after ban expires
        return to == HandshakeState.locked;
    }
  }

  void _startHandshakeTimeout() {
    _cancelHandshakeTimeout();
    _handshakeTimeout = Timer(_timeoutDuration, () {
      if (_state == HandshakeState.authenticating) {
        _logger.warning(
          'Handshake timeout: No response from server after ${_timeoutDuration.inSeconds}s',
        );
        transitionTo(HandshakeState.failed);
      }
    });
  }

  void _cancelHandshakeTimeout() {
    _handshakeTimeout?.cancel();
    _handshakeTimeout = null;
  }
}
