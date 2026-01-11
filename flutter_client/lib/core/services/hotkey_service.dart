import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:flutter_client/core/services/logging_service.dart';

class HotkeyService {
  static final HotkeyService _instance = HotkeyService._internal();
  factory HotkeyService() => _instance;
  HotkeyService._internal();

  // The thread ID of the running isolate (needed to wake it up)
  int? _isolateThreadId;
  Isolate? _isolate;

  final StreamController<int> _hotkeyStreamController =
      StreamController<int>.broadcast();
  Stream<int> get onHotkeyPressed => _hotkeyStreamController.stream;

  bool get isRunning => _isolate != null;

  /// Starts the hotkey listener with the given configuration.
  /// If already running, it restarts the service (kill & respawn).
  Future<void> start({
    required int id,
    required int modifiers,
    required int vKey,
  }) async {
    if (isRunning) {
      await stop();
    }

    LoggingService().info(
      'Starting HotkeyService (Native Blocking Loop)...',
      sendToServer: false,
    );

    final receivePort = ReceivePort();

    // Spawn the isolate with the configuration
    _isolate = await Isolate.spawn(
      _isolateEntry,
      _HotkeyConfig(receivePort.sendPort, id, modifiers, vKey),
    );

    // Watch for unexpected crashes
    _isolate!.addOnExitListener(receivePort.sendPort, response: 'EXIT');

    final completer = Completer<void>();

    // Listen for messages from the isolate
    receivePort.listen((message) {
      if (message is int) {
        // This is the Thread ID sent during initialization
        _isolateThreadId = message;
        if (!completer.isCompleted) completer.complete();
      } else if (message == 'HOTKEY') {
        // Hotkey pressed!
        _hotkeyStreamController.add(1); // We only use ID 1 for now
      } else if (message == 'EXIT') {
        // Isolate exited (crash or manual stop)
        LoggingService().warning('Hotkey isolate exited.');
        _isolateThreadId = null;
        _isolate = null;
        receivePort.close();
      } else if (message is String && message.startsWith('ERROR:')) {
        LoggingService().error('Hotkey Isolate: $message');
      }
    });

    await completer.future;
    LoggingService().info('HotkeyService started successfully.');
  }

  /// Stops the hotkey listener by posting a Quit message to the thread.
  Future<void> stop() async {
    if (_isolateThreadId != null) {
      // WM_QUIT = 0x0012
      // PostThreadMessage puts a message in the thread's queue, waking up GetMessage
      final result = PostThreadMessage(_isolateThreadId!, WM_QUIT, 0, 0);
      if (result == 0) {
        LoggingService().error(
          'Failed to post WM_QUIT to isolate thread: ${GetLastError()}',
        );
        // Fallback to hard kill
        _isolate?.kill(priority: Isolate.immediate);
      }
    }

    // Allow some time for graceful shutdown
    await Future.delayed(const Duration(milliseconds: 50));

    if (_isolate != null) {
      // Ensure it's dead if graceful shutdown failed
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
    }
    _isolateThreadId = null;
    LoggingService().info('HotkeyService stopped.');
  }

  // --- Static Isolate Entry Point ---
  static void _isolateEntry(_HotkeyConfig config) {
    try {
      // 1. Register Hotkey
      // This function call creates the message queue for the thread if it doesn't exist
      final result = RegisterHotKey(
        NULL,
        config.id,
        config.modifiers,
        config.vKey,
      );

      if (result == 0) {
        final error = GetLastError();
        config.sendPort.send('ERROR: Failed to register hotkey (Error $error)');
        return;
      }

      // 2. Send Thread ID back to main isolate so it can wake us up later
      final threadId = GetCurrentThreadId();
      config.sendPort.send(threadId);

      // 3. Enter Blocking Message Loop (Deep Sleep Proof)
      final msg = calloc<MSG>();

      // GetMessage blocks until a message arrives.
      // Returns > 0 for normal messages
      // Returns 0 for WM_QUIT
      // Returns -1 for error
      while (GetMessage(msg, NULL, 0, 0) > 0) {
        if (msg.ref.message == WM_HOTKEY) {
          config.sendPort.send('HOTKEY');
        }

        TranslateMessage(msg);
        DispatchMessage(msg);
      }

      // 4. Cleanup
      UnregisterHotKey(NULL, config.id);
      free(msg);
    } catch (e) {
      config.sendPort.send('ERROR: Isolate Crash: $e');
    }
  }
}

/// Configuration object passed to the isolate
class _HotkeyConfig {
  final SendPort sendPort;
  final int id;
  final int modifiers;
  final int vKey;

  _HotkeyConfig(this.sendPort, this.id, this.modifiers, this.vKey);
}
