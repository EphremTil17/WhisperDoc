import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'logging_service.dart';

class HotkeyService {
  static final HotkeyService _instance = HotkeyService._internal();
  factory HotkeyService() => _instance;
  HotkeyService._internal();

  SendPort? _isolateSendPort;
  final StreamController<int> _hotkeyStreamController =
      StreamController<int>.broadcast();
  Stream<int> get onHotkeyPressed => _hotkeyStreamController.stream;

  Future<void> start() async {
    if (_isolateSendPort != null) return;

    LoggingService().info('Starting HotkeyService...', sendToServer: false);

    final receivePort = ReceivePort();
    await Isolate.spawn(_isolateEntry, receivePort.sendPort);

    // Wait for the isolate to send back its SendPort
    final completer = Completer<SendPort>();
    receivePort.listen((message) {
      if (message is SendPort) {
        if (!completer.isCompleted) completer.complete(message);
      } else if (message is int) {
        _hotkeyStreamController.add(message);
      } else if (message is _HotkeyLog) {
        if (message.isError) {
          LoggingService().error(message.message, sendToServer: false);
        } else {
          LoggingService().info(message.message, sendToServer: false);
        }
      }
    });

    _isolateSendPort = await completer.future;
    LoggingService().info(
      'HotkeyService started successfully.',
      sendToServer: false,
    );
  }

  /// vKey: Virtual Key Code (e.g. VK_F9 is 0x78)
  /// modifiers: MOD_ALT (1), MOD_CONTROL (2), MOD_SHIFT (4), MOD_WIN (8)
  Future<void> registerHotkey({
    required int id,
    required int modifiers,
    required int vKey,
  }) async {
    _isolateSendPort?.send(_HotkeyCommand(id, modifiers, vKey));
  }

  Future<void> unregisterHotkey(int id) async {
    _isolateSendPort?.send(_HotkeyUnregister(id));
  }

  static void _isolateEntry(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    // Keep references to registered hotkeys if needed

    // Commands Stream
    receivePort.listen((message) {
      if (message is _HotkeyCommand) {
        // Always try to unregister first to avoid 1409
        UnregisterHotKey(NULL, message.id);

        final result = RegisterHotKey(
          NULL,
          message.id,
          message.modifiers,
          message.vKey,
        );
        if (result == 0) {
          mainSendPort.send(
            _HotkeyLog(
              'Isolate: Failed to register hotkey ${message.id} (Error ${GetLastError()})',
              isError: true,
            ),
          );
        }
      } else if (message is _HotkeyUnregister) {
        UnregisterHotKey(NULL, message.id);
      }
    });

    // Message Loop via Timer (Polling)
    final msg = calloc<MSG>();

    Timer.periodic(const Duration(milliseconds: 10), (timer) {
      while (PeekMessage(msg, NULL, 0, 0, PM_REMOVE) != 0) {
        if (msg.ref.message == WM_HOTKEY) {
          mainSendPort.send(msg.ref.wParam);
        }
        TranslateMessage(msg);
        DispatchMessage(msg);
      }
    });
  }
}

class _HotkeyCommand {
  final int id;
  final int modifiers;
  final int vKey;
  _HotkeyCommand(this.id, this.modifiers, this.vKey);
}

class _HotkeyUnregister {
  final int id;
  _HotkeyUnregister(this.id);
}

class _HotkeyLog {
  final String message;
  final bool isError;
  _HotkeyLog(this.message, {this.isError = false});
}
