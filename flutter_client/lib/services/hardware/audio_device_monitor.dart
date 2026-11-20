import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/services/utility/logging_service.dart';

/// Push-based notifications that the OS audio endpoint set may have changed.
///
/// The Windows runner registers a Core Audio `IMMNotificationClient` and
/// forwards device added/removed/state/default-capture changes over
/// [channelName]. Nothing polls: when devices are stable no work happens.
///
/// One physical plug/unplug produces a short burst of native notifications
/// (~40 ms measured with a USB mic). [changes] emits once the burst has been
/// quiet for [settle]: Windows' device list lags the first notification in
/// both directions, so an immediate re-check would read stale state.
class AudioDeviceMonitor {
  /// Must match `kAudioDevicesChannel` in `windows/runner/flutter_window.cpp`.
  static const String channelName = 'whisperdoc/audio_devices';
  static const String _changedMethod = 'audioDevicesChanged';

  final MethodChannel _channel;
  final Duration _settle;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  final Stopwatch _burstClock = Stopwatch();
  Timer? _settleTimer;
  int _burstNotifications = 0;

  AudioDeviceMonitor({
    MethodChannel channel = const MethodChannel(channelName),
    Duration settle = AppConstants.audioDeviceChangeSettle,
  }) : _channel = channel,
       _settle = settle;

  /// Emits once per settled burst of endpoint changes.
  Stream<void> get changes => _changes.stream;

  /// Starts listening for native notifications. Call after the Flutter
  /// binding is initialized.
  void start() => _channel.setMethodCallHandler(_handleCall);

  Future<void> _handleCall(MethodCall call) async {
    if (call.method != _changedMethod) return;
    if (_burstNotifications == 0) {
      _burstClock
        ..reset()
        ..start();
    }
    _burstNotifications++;
    _settleTimer?.cancel();
    _settleTimer = Timer(_settle, _endBurst);
  }

  void _endBurst() {
    LoggingService().debug(
      'Audio endpoints changed: $_burstNotifications OS notification(s), '
      're-checking ${_burstClock.elapsedMilliseconds} ms after the first',
    );
    _burstClock.stop();
    _burstNotifications = 0;
    _changes.add(null);
  }

  Future<void> dispose() async {
    _channel.setMethodCallHandler(null);
    _settleTimer?.cancel();
    await _changes.close();
  }
}
