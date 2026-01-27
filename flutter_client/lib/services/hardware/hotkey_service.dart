import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:flutter_client/services/utility/logging_service.dart';

class HotkeyService {
  static final HotkeyService _instance = HotkeyService._internal();
  factory HotkeyService() => _instance;
  HotkeyService._internal();

  // Isolate state
  int? _isolateThreadId;
  Isolate? _isolate;
  ReceivePort? _receivePort;
  StreamSubscription? _portSubscription;
  Completer<void>? _exitCompleter;

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
    // Stop any existing isolate first
    if (isRunning) {
      await stop();
    }

    LoggingService().info(
      'Starting HotkeyService (Native Blocking Loop)...',
      sendToServer: false,
    );

    // Create fresh state for this session
    _receivePort = ReceivePort();
    _exitCompleter = Completer<void>();
    final startCompleter = Completer<void>();

    // Set up listener BEFORE spawning isolate
    _portSubscription = _receivePort!.listen((message) {
      if (message is int) {
        // This is the Thread ID sent during initialization
        _isolateThreadId = message;
        if (!startCompleter.isCompleted) startCompleter.complete();
      } else if (message == 'HOTKEY') {
        // Hotkey pressed!
        _hotkeyStreamController.add(1);
      } else if (message == 'EXIT') {
        // Isolate exited - signal the exitCompleter
        if (_exitCompleter != null && !_exitCompleter!.isCompleted) {
          _exitCompleter!.complete();
        }
      } else if (message is String && message.startsWith('ERROR:')) {
        LoggingService().error('Hotkey Isolate: $message');
      }
    });

    // Spawn the isolate
    _isolate = await Isolate.spawn(
      _isolateEntry,
      _HotkeyConfig(_receivePort!.sendPort, id, modifiers, vKey),
    );

    // Watch for unexpected crashes
    _isolate!.addOnExitListener(_receivePort!.sendPort, response: 'EXIT');

    // Wait for thread ID (indicates successful start)
    await startCompleter.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        LoggingService().error('HotkeyService start timed out');
      },
    );

    if (_isolateThreadId != null) {
      LoggingService().info('HotkeyService started successfully.');
    }
  }

  /// Stops the hotkey listener by posting a Quit message to the thread.
  Future<void> stop() async {
    if (_isolate == null) return;

    // Ensure we have an exit completer to wait on
    _exitCompleter ??= Completer<void>();

    if (_isolateThreadId != null) {
      // Post WM_QUIT to wake up the blocking GetMessage loop
      final result = PostThreadMessage(_isolateThreadId!, WM_QUIT, 0, 0);
      if (result == 0) {
        // PostThreadMessage failed, force kill
        _isolate?.kill(priority: Isolate.immediate);
        if (!_exitCompleter!.isCompleted) _exitCompleter!.complete();
      }
    } else {
      // No thread ID, just kill
      _isolate?.kill(priority: Isolate.immediate);
      if (!_exitCompleter!.isCompleted) _exitCompleter!.complete();
    }

    // Wait for graceful exit or timeout
    await _exitCompleter!.future.timeout(
      const Duration(milliseconds: 300),
      onTimeout: () {
        _isolate?.kill(priority: Isolate.immediate);
      },
    );

    // Clean up all state
    await _portSubscription?.cancel();
    _portSubscription = null;
    _receivePort?.close();
    _receivePort = null;
    _isolate = null;
    _isolateThreadId = null;
    _exitCompleter = null;

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
