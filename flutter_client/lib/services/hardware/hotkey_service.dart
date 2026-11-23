import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';
import 'package:flutter_client/services/utility/logging_service.dart';

/// Entry point of the listener isolate. Production registers the real global
/// hotkey; tests substitute one that registers nothing.
typedef HotkeyListener = void Function(HotkeyListenerConfig config);

/// Wakes the listener thread so its message loop ends. False if it couldn't.
typedef ThreadWaker = bool Function(int threadId);

class HotkeyService {
  static final LoggingService _logger = LoggingService();

  static final HotkeyService _instance = HotkeyService._internal();
  static const MethodChannel _lifecycleChannel = MethodChannel(
    'whisperdoc/hotkey_lifecycle',
  );
  static const Duration _startTimeout = Duration(seconds: 2);
  static const Duration _stopTimeout = Duration(milliseconds: 300);

  /// GetMessageW with its raw return. package:win32 maps the BOOL to `bool`,
  /// which folds the -1 error return into `true`; the message loop must stop
  /// on errors instead of spinning.
  static final _getMessage = DynamicLibrary.open('user32.dll')
      .lookupFunction<
        Int32 Function(Pointer<MSG>, Pointer, Uint32, Uint32),
        int Function(Pointer<MSG>, Pointer, int, int)
      >('GetMessageW');

  final HotkeyListener _listen;
  final ThreadWaker _wake;

  // Isolate state
  int? _isolateThreadId;
  Isolate? _isolate;
  ReceivePort? _receivePort;
  StreamSubscription? _portSubscription;
  Completer<void>? _exitCompleter;

  /// Start, stop and resume run one at a time: an exit arriving mid-spawn
  /// must wait for the spawn rather than miss the isolate it is creating.
  Future<void> _queue = Future.value();

  final StreamController<int> _hotkeyStreamController =
      StreamController<int>.broadcast();
  final StreamController<void> _refusedController =
      StreamController<void>.broadcast();

  /// The last binding passed to [start], so [resume] can restore it.
  ({int id, int modifiers, int vKey})? _binding;

  Stream<int> get onHotkeyPressed => _hotkeyStreamController.stream;

  /// Windows refused the shortcut (another app holds the combination) or the
  /// listener never started, so pressing it does nothing.
  Stream<void> get onRefused => _refusedController.stream;
  bool get isRunning => _isolate != null;

  factory HotkeyService() => _instance;
  HotkeyService._internal() : _listen = _isolateEntry, _wake = _postQuit;

  @visibleForTesting
  HotkeyService.withListener(this._listen, this._wake);

  /// Registers the global shortcut, replacing any current one. True once
  /// Windows accepted it; false (and [onRefused]) when it didn't.
  Future<bool> start({
    required int id,
    required int modifiers,
    required int vKey,
  }) => _serialized(() => _start(id: id, modifiers: modifiers, vKey: vKey));

  /// Restarts the last binding after a [stop] (for example once the shortcut
  /// recorder closes without a new one). True if a shortcut is registered.
  Future<bool> resume() => _serialized(() async {
    final binding = _binding;
    if (binding == null || isRunning) return isRunning;

    return _start(
      id: binding.id,
      modifiers: binding.modifiers,
      vKey: binding.vKey,
    );
  });

  /// Releases the shortcut and ends the listener isolate.
  Future<void> stop() => _serialized(_stop);

  Future<T> _serialized<T>(Future<T> Function() operation) async {
    final previous = _queue;
    final done = Completer<void>();
    _queue = done.future;
    await previous;
    try {
      return await operation();
    } finally {
      done.complete();
    }
  }

  Future<bool> _start({
    required int id,
    required int modifiers,
    required int vKey,
  }) async {
    if (isRunning) await _stop();
    _binding = (id: id, modifiers: modifiers, vKey: vKey);

    _logger.info('Starting HotkeyService (Native Blocking Loop)...');

    // Create fresh state for this session
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    final exitCompleter = Completer<void>();
    _exitCompleter = exitCompleter;
    final registered = Completer<bool>();

    // Set up listener BEFORE spawning isolate
    _portSubscription = receivePort.listen((message) {
      if (message is int) {
        // This is the Thread ID sent once the hotkey is registered. Hand it
        // to the runner at once, not after start() resumes: a window close
        // in between would otherwise find no thread to wake.
        _isolateThreadId = message;
        unawaited(_reportNativeThreadId(message));
        if (!registered.isCompleted) registered.complete(true);
      } else if (message == 'HOTKEY') {
        _hotkeyStreamController.add(1);
      } else if (message == null) {
        // The isolate exited (onExit). Its thread is gone (and its id may
        // be reused by any process), so withdraw it from the runner's
        // close-time WM_QUIT, and stop reporting a running listener.
        _isolateThreadId = null;
        _isolate = null;
        unawaited(_reportNativeThreadId(0));
        if (!exitCompleter.isCompleted) exitCompleter.complete();
        if (!registered.isCompleted) registered.complete(false);
      } else if (message is String && message.startsWith('ERROR:')) {
        _logger.error('Hotkey Isolate: $message');
        if (!registered.isCompleted) registered.complete(false);
      }
    });

    try {
      _isolate = await Isolate.spawn(
        _listen,
        HotkeyListenerConfig(receivePort.sendPort, id, modifiers, vKey),
        onExit: receivePort.sendPort,
      );
    } on IsolateSpawnException catch (e) {
      _logger.error('Hotkey listener could not start: $e');
      registered.complete(false);
    }

    final accepted = await registered.future.timeout(
      _startTimeout,
      onTimeout: () => false,
    );
    if (accepted) {
      _logger.info('HotkeyService started successfully.');

      return true;
    }

    _logger.error('Shortcut not registered; it may be in use by another app');
    await _stop();
    _refusedController.add(null);

    return false;
  }

  Future<void> _stop() async {
    final isolate = _isolate;
    if (isolate != null) {
      final exited = _exitCompleter ?? Completer<void>();
      final threadId = _isolateThreadId;
      // Post WM_QUIT to wake the blocking GetMessage loop; without a thread
      // (not registered yet) or if posting fails, end the isolate outright.
      final woken = threadId != null && _wake(threadId);
      if (!woken) isolate.kill(priority: Isolate.immediate);

      await exited.future.timeout(
        _stopTimeout,
        onTimeout: () => isolate.kill(priority: Isolate.immediate),
      );
      unawaited(_reportNativeThreadId(0));
    }

    // Clean up all state
    await _portSubscription?.cancel();
    _portSubscription = null;
    _receivePort?.close();
    _receivePort = null;
    _isolate = null;
    _isolateThreadId = null;
    _exitCompleter = null;

    if (isolate != null) _logger.info('HotkeyService stopped.');
  }

  static bool _postQuit(int threadId) => PostThreadMessage(
    threadId,
    WM_QUIT,
    const WPARAM(0),
    const LPARAM(0),
  ).value;

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
  static void _isolateEntry(HotkeyListenerConfig config) {
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

/// What the listener isolate needs: where to report, and the binding.
class HotkeyListenerConfig {
  final SendPort sendPort;
  final int id;
  final int modifiers;
  final int vKey;

  HotkeyListenerConfig(this.sendPort, this.id, this.modifiers, this.vKey);
}
