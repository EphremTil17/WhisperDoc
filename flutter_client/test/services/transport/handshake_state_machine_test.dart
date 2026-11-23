// ignore_for_file: avoid-late-keyword
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/services/transport/handshake_state_machine.dart';

void main() {
  late HandshakeStateMachine machine;

  setUp(() {
    machine = HandshakeStateMachine();
  });

  tearDown(() {
    machine.dispose();
  });

  group('HandshakeStateMachine - State Transitions', () {
    test('Initial state should be locked', () {
      expect(machine.state, equals(HandshakeState.locked));
      expect(machine.canSendAudio(), isFalse);
    });

    test('locked -> authenticating is valid', () {
      machine.transitionTo(HandshakeState.authenticating);
      expect(machine.state, equals(HandshakeState.authenticating));
      expect(machine.canSendAudio(), isFalse);
    });

    test('authenticating -> authenticated is valid', () {
      machine.transitionTo(HandshakeState.authenticating);
      machine.transitionTo(HandshakeState.authenticated);
      expect(machine.state, equals(HandshakeState.authenticated));
      expect(machine.canSendAudio(), isTrue);
    });

    test('authenticating -> failed is valid', () {
      machine.transitionTo(HandshakeState.authenticating);
      machine.transitionTo(HandshakeState.failed);
      expect(machine.state, equals(HandshakeState.failed));
      expect(machine.canSendAudio(), isFalse);
    });

    test('banned is reachable from locked', () {
      machine.transitionTo(HandshakeState.banned);
      expect(machine.state, equals(HandshakeState.banned));
    });

    test('banned is reachable from authenticating', () {
      machine.transitionTo(HandshakeState.authenticating);
      machine.transitionTo(HandshakeState.banned);
      expect(machine.state, equals(HandshakeState.banned));
    });

    test('Invalid transition should be ignored and logged', () {
      // locked -> authenticated is direct and invalid (must go through authenticating)
      machine.transitionTo(HandshakeState.authenticated);
      expect(machine.state, equals(HandshakeState.locked));
    });
  });

  group('HandshakeStateMachine - Recovery', () {
    test('reset() should return to locked', () {
      machine.transitionTo(HandshakeState.authenticating);
      machine.transitionTo(HandshakeState.failed);
      machine.reset();
      expect(machine.state, equals(HandshakeState.locked));
    });

    // Regression: _handleDisconnect() used to unconditionally call reset(), wiping
    // HandshakeState.failed before the UI could read it. The fix guards the reset
    // with (state != failed). This test encodes that invariant directly.
    test(
      'failed state is preserved when reset is skipped (disconnect guard)',
      () {
        machine.transitionTo(HandshakeState.authenticating);
        machine.transitionTo(HandshakeState.failed);

        // Simulate what the guarded _handleDisconnect() now does:
        if (machine.state != HandshakeState.failed) machine.reset();

        expect(
          machine.state,
          equals(HandshakeState.failed),
          reason: 'UI needs the failed state to survive the disconnect path',
        );

        // The next connect() call issues an unconditional reset — verify recovery.
        machine.reset();
        expect(machine.state, equals(HandshakeState.locked));
      },
    );
  });

  // testWidgets runs on a fake clock, so tester.pump(duration) passes the
  // handshake timeout without waiting for it.
  group('HandshakeStateMachine - Timeout', () {
    const timeout = Duration(seconds: 15);
    const tick = Duration(milliseconds: 1);

    testWidgets('authenticating fails once the server stays silent for 15 s', (
      tester,
    ) async {
      machine.transitionTo(HandshakeState.authenticating);

      await tester.pump(timeout - tick);
      expect(machine.state, equals(HandshakeState.authenticating));

      await tester.pump(tick);
      expect(machine.state, equals(HandshakeState.failed));
    });

    testWidgets('an answer in time keeps the session authenticated', (
      tester,
    ) async {
      machine.transitionTo(HandshakeState.authenticating);
      await tester.pump(timeout - tick);
      machine.transitionTo(HandshakeState.authenticated);

      await tester.pump(timeout);
      expect(machine.state, equals(HandshakeState.authenticated));
    });

    testWidgets(
      'a reset in time stays locked, a new attempt gets the full 15 s',
      (tester) async {
        machine.transitionTo(HandshakeState.authenticating);
        await tester.pump(timeout - tick);
        machine.reset();

        await tester.pump(timeout);
        expect(machine.state, equals(HandshakeState.locked));

        machine.transitionTo(HandshakeState.authenticating);
        await tester.pump(timeout - tick);
        expect(machine.state, equals(HandshakeState.authenticating));

        await tester.pump(tick);
        expect(machine.state, equals(HandshakeState.failed));
      },
    );
  });
}
