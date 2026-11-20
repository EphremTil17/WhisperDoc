// ignore_for_file: avoid-late-keyword, no-magic-number, prefer-match-file-name, prefer-moving-to-variable
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/services/hardware/audio_device_monitor.dart';

/// Simulates the Windows runner invoking methods on the Dart side.
abstract final class _NativeRunner {
  static Future<void> send(String method) async {
    const codec = StandardMethodCodec();
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          AudioDeviceMonitor.channelName,
          codec.encodeMethodCall(MethodCall(method)),
          null,
        );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const settle = Duration(milliseconds: 30);
  late AudioDeviceMonitor monitor;
  late int emissions;

  setUp(() {
    monitor = AudioDeviceMonitor(settle: settle)..start();
    emissions = 0;
    monitor.changes.listen((_) => emissions++);
  });

  tearDown(() => monitor.dispose());

  test('collapses a burst of native notifications into one re-check', () async {
    // One physical plug-in fires several endpoint callbacks.
    for (var i = 0; i < 5; i++) {
      await _NativeRunner.send('audioDevicesChanged');
    }
    await Future<void>.delayed(Duration.zero);
    expect(emissions, isZero, reason: "the device list lags the first event");

    await Future<void>.delayed(settle * 3);
    expect(emissions, equals(1));
  });

  test('separate bursts re-check separately', () async {
    await _NativeRunner.send('audioDevicesChanged');
    await Future<void>.delayed(settle * 3);
    await _NativeRunner.send('audioDevicesChanged');
    await Future<void>.delayed(settle * 3);

    expect(emissions, equals(2));
  });

  test('ignores unrelated methods on the channel', () async {
    await _NativeRunner.send('somethingElse');
    await Future<void>.delayed(settle * 3);

    expect(emissions, isZero);
  });
}
