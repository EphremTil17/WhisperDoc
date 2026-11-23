import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';
import 'package:flutter_client/services/utility/logging_service.dart';

class HotkeyService {
  static final LoggingService _logger = LoggingService();

  static final HotkeyService _instance = HotkeyService._internal();
  static const MethodChannel _lifecycleChannel = MethodChannel(
    'whisperdoc/hotkey_lifecycle',
  );

  /// GetMessageW with its raw return. package:win32 maps the BOOL to `bool`,
  /// which folds the -1 error return into `true`; the message loop must stop
  /// on errors instead of spinning.
  static final _getMessage = DynamicLibrary.open('user32.dll')
      .lookupFunction<
        Int32 Function(Pointer<MSG>, Pointer, Uint32, Uint32),
        int Function(Pointer<MSG>, Pointer, int, int)
      >('GetMessageW');

  // Isolate state
  int? _isolateThreadId;
  Isolate? _isolate;
  ReceivePort? _receivePort;
  StreamSubscription? _portSubscription;
  Completer<void>? _exitCompleter;

  final StreamController<int> _hotkeyStreamController =
      StreamController<int>.broadcast();

  /// The last binding passed to [start], so [resume] can restore it.
  ({int id, int modifiers, int vKey})? _binding;

  Stream<int> get onHotkeyPressed => _hotkeyStreamController.stream;
  bool get isRunning => _isolate != null;

  factory HotkeyService() => _instance;
  HotkeyService._internal();

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
    _binding = (id: id, modifiers: modifiers, vKey: vKey);

    _logger.info('Starting HotkeyService (Native Blocking Loop)...');

    // Create fresh state for this session
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    final exitCompleter = Completer<void>();
    _exitCompleter = exitCompleter;
    final startCompleter = Completer<void>();

    // Set up listener BEFORE spawning isolate
    _portSubscription = receivePort.listen((message) {
      if (message is int) {
        // This is the Thread ID sent during initialization. Hand it to the
        // runner at once, not after start() resumes: a window close in
        // between would otherwise find no thread to wake.
        _isolateThreadId = message;
        unawaited(_reportNativeThreadId(message));
        if (!startCompleter.isCompleted) startCompleter.complete();
      } else if (message == 'HOTKEY') {
        // Hotkey pressed!
        _hotkeyStreamController.add(1);
      } else if (message == 'EXIT') {
        // Isolate exited - signal the exitCompleter. Its thread is gone (and
        // its id may be reused by any process), so withdraw it from the
        // runner's close-time WM_QUIT.
        _isolateThreadId = null;
        unawaited(_reportNativeThreadId(0));
        if (!exitCompleter.isCompleted) {
          exitCompleter.complete();
        }
      } else if (message is String && message.startsWith('ERROR:')) {
        _logger.error('Hotkey Isolate: $message');
      }
    });

    // Spawn the isolate
    final isolate = await Isolate.spawn(
      _isolateEntry,
      _HotkeyConfig(receivePort.sendPort, id, modifiers, vKey),
    );
    _isolate = isolate;

    // Watch for unexpected crashes
    isolate.addOnExitListener(receivePort.sendPort, response: 'EXIT');

    // Wait for thread ID (indicates successful start)
    await startCompleter.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        _logger.error('HotkeyService start timed out');
      },
    );

    if (_isolateThreadId != null) {
      _logger.info('HotkeyService started successfully.');
    }
  }

  /// Restarts the last binding after a [stop] (for example once the shortcut
  /// recorder closes without a new one). Does nothing if already running.
  Future<void> resume() async {
    final binding = _binding;
    if (binding == null || isRunning) return;
    await start(
      id: binding.id,
      modifiers: binding.modifiers,
      vKey: binding.vKey,
    );
  }

  /// Stops the hotkey listener by posting a Quit message to the thread.
  Future<void> stop() async {
    if (_isolate == null) return;

    // Ensure we have an exit completer to wait on
    final exitCompleter = _exitCompleter ??= Completer<void>();
    final threadId = _isolateThreadId;

    if (threadId != null) {
      // Post WM_QUIT to wake up the blocking GetMessage loop
      final posted = PostThreadMessage(
        threadId,
        WM_QUIT,
        const WPARAM(0),
        const LPARAM(0),
      ).value;
      if (!posted) {
        // PostThreadMessage failed, force kill
        _isolate?.kill(priority: Isolate.immediate);
        if (!exitCompleter.isCompleted) exitCompleter.complete();
      }
    } else {
      // No thread ID, just kill
      _isolate?.kill(priority: Isolate.immediate);
      if (!exitCompleter.isCompleted) exitCompleter.complete();
    }

    // Wait for graceful exit or timeout
    await exitCompleter.future.timeout(
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
    unawaited(_reportNativeThreadId(0));

    _logger.info('HotkeyService stopped.');
  }

  static Future<void> _reportNativeThreadId(int threadId) async {
    try {
      await _lifecycleChannel.invokeMethod<void>('setHotkeyThreadId', threadId);
    } on MissingPluginException {
      // Headless tests have no native Windows runner.
    } catch (_) {
      // Best-effort native shutdown guard; Dart exit handler still calls stop().
    }
  }

  // --- Static Isolate Entry Point ---
  static void _isolateEntry(_HotkeyConfig config) {
    try {
      // 1. Register Hotkey
      // This function call creates the message queue for the thread if it doesn't exist
      final Win32Result(value: registered, :error) = RegisterHotKey(
        null,
        config.id,
        HOT_KEY_MODIFIERS(config.modifiers),
        config.vKey,
      );

      if (!registered) {
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
      while (_getMessage(msg, nullptr, 0, 0) > 0) {
        if (msg.ref.message == WM_HOTKEY) {
          config.sendPort.send('HOTKEY');
        }

        TranslateMessage(msg);
        DispatchMessage(msg);
      }

      // 4. Cleanup
      UnregisterHotKey(null, config.id);
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
