import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/services/hardware/hotkey_service.dart';

// Each start, stop or resume call is a separate request the test makes on
// purpose (two starts, a resume before and after), so they can't share one.
// The first class holds the fake listeners, which must be static to run as
// isolate entry points; the file is named for the service under test.
// ignore_for_file: prefer-moving-to-variable, prefer-match-file-name

/// Listener isolates for the seam. They register nothing with Windows, so
/// the tests never claim a real global shortcut on the machine running them.
abstract final class _Listeners {
  static const int threadId = 4242;

  /// Accepts the shortcut, reports one press, and stays alive like the real
  /// message loop (an open port keeps the isolate running).
  static void accepting(HotkeyListenerConfig config) {
    RawReceivePort();
    config.sendPort
      ..send(threadId)
      ..send('HOTKEY');
  }

  /// Windows refused the combination (ERROR_HOTKEY_ALREADY_REGISTERED).
  static void refused(HotkeyListenerConfig config) {
    config.sendPort.send('ERROR: Failed to register hotkey (Error 1409)');
  }

  /// Never reports back, like a listener stuck before registering.
  static void silent(HotkeyListenerConfig _) {
    RawReceivePort();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const binding = (id: 1, modifiers: 2, vKey: 0x45);

  /// A service whose listener is [listen]; [woken] records each thread it
  /// was asked to wake. Waking "fails" so stop ends the isolate at once.
  HotkeyService serviceWith(HotkeyListener listen, List<int> woken) {
    final service = HotkeyService.withListener(listen, (threadId) {
      woken.add(threadId);

      return false;
    });
    addTearDown(service.stop);

    return service;
  }

  Future<bool> startOn(HotkeyService service) => service.start(
    id: binding.id,
    modifiers: binding.modifiers,
    vKey: binding.vKey,
  );

  group('HotkeyService', () {
    test('the app uses one shared instance', () {
      expect(identical(HotkeyService(), HotkeyService()), isTrue);
    });

    test('an accepted shortcut runs and reports presses', () async {
      final service = serviceWith(_Listeners.accepting, []);
      final pressed = service.onHotkeyPressed.first;

      expect(await startOn(service), isTrue);
      expect(service.isRunning, isTrue);
      expect(await pressed.timeout(const Duration(seconds: 2)), 1);
    });

    test('a refused shortcut says so and does not count as running', () async {
      final service = serviceWith(_Listeners.refused, []);
      var refusals = 0;
      service.onRefused.listen((_) => refusals++);

      expect(await startOn(service), isFalse);
      await pumpEventQueue();

      expect(service.isRunning, isFalse);
      expect(refusals, 1);
    });

    test('a listener that never reports back is ended and refused', () async {
      final service = serviceWith(_Listeners.silent, []);

      expect(await startOn(service), isFalse);
      expect(service.isRunning, isFalse);
    });

    test(
      'stop during start waits for it, so nothing is left running',
      () async {
        final service = serviceWith(_Listeners.accepting, []);

        final starting = startOn(service);
        final stopping = service.stop();
        await Future.wait([starting, stopping]);

        expect(await starting, isTrue);
        expect(service.isRunning, isFalse);
      },
    );

    test('a second start replaces the first listener', () async {
      final woken = <int>[];
      final service = serviceWith(_Listeners.accepting, woken);

      final results = await Future.wait([startOn(service), startOn(service)]);

      expect(results, [true, true]);
      expect(woken, [
        _Listeners.threadId,
      ], reason: 'the first listener was ended');
      expect(service.isRunning, isTrue);
    });

    test('resume restores the last shortcut after a stop', () async {
      final service = serviceWith(_Listeners.accepting, []);
      expect(await service.resume(), isFalse, reason: 'nothing to restore yet');

      await startOn(service);
      await service.stop();
      expect(service.isRunning, isFalse);

      expect(await service.resume(), isTrue);
      expect(service.isRunning, isTrue);
    });
  });
}
