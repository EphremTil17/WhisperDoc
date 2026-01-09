import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'logging_service.dart';

class ClipboardService {
  static Future<void> copyToClipboard(String text) async {
    if (text.isEmpty) return;

    // Use Win32 API directly for reliability
    final units = text.codeUnits;
    final size = (units.length + 1) * 2; // UTF-16 + null terminator

    final hMem = GlobalAlloc(GMEM_MOVEABLE, size);
    if (hMem == nullptr) return;

    final pMem = GlobalLock(hMem);
    if (pMem == nullptr) {
      GlobalFree(hMem);
      return;
    }

    final ptr = pMem.cast<Uint16>();
    for (var i = 0; i < units.length; i++) {
      ptr[i] = units[i];
    }
    ptr[units.length] = 0; // Null terminator

    GlobalUnlock(hMem);

    // Retry opening clipboard a few times as it might be locked by another app
    bool success = false;
    for (var i = 0; i < 5; i++) {
      if (OpenClipboard(0) != 0) {
        EmptyClipboard();
        // win32 v5.x SetClipboardData expects int (handle address), not Pointer
        SetClipboardData(CF_UNICODETEXT, hMem.address);
        CloseClipboard();
        success = true;
        break;
      }
      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (success) {
      LoggingService().info(
        'Text copied to clipboard (Win32)',
        sendToServer: false,
      );
    } else {
      GlobalFree(hMem);
      LoggingService().error('Failed to open clipboard', sendToServer: false);
    }
  }

  /// Simulates Ctrl+V on Windows using the SendInput API.
  static Future<void> simulatePaste() async {
    LoggingService().info(
      'Simulating Ctrl+V via SendInput...',
      sendToServer: false,
    );

    final inputs = calloc<INPUT>(1);
    try {
      // Helper function to send a single key event
      void sendKey(int vKey, bool isKeyUp) {
        inputs[0].type = INPUT_KEYBOARD;
        inputs[0].ki.wVk = vKey;
        inputs[0].ki.dwFlags = isKeyUp ? KEYEVENTF_KEYUP : 0;
        SendInput(1, inputs, sizeOf<INPUT>());
      }

      // 1. Force release all possible modifiers to ensure Ctrl+V isn't blocked
      const modifiers = [
        VK_SHIFT,
        VK_LSHIFT,
        VK_RSHIFT,
        VK_MENU,
        VK_LMENU,
        VK_RMENU,
        VK_LWIN,
        VK_RWIN,
        VK_CONTROL,
        VK_LCONTROL,
        VK_RCONTROL,
      ];

      for (var mod in modifiers) {
        sendKey(mod, true);
      }
      await Future.delayed(const Duration(milliseconds: 10));

      // 2. Perform Paste Sequence: Ctrl Down -> V Down -> V Up -> Ctrl Up
      sendKey(VK_CONTROL, false);
      await Future.delayed(const Duration(milliseconds: 10));
      sendKey(0x56, false); // V down
      await Future.delayed(const Duration(milliseconds: 10));
      sendKey(0x56, true); // V up
      await Future.delayed(const Duration(milliseconds: 10));
      sendKey(VK_CONTROL, true);

      LoggingService().info('Paste simulation complete', sendToServer: false);
    } catch (e) {
      LoggingService().error(
        'Paste simulation failed: $e',
        sendToServer: false,
      );
    } finally {
      free(inputs);
    }
  }
}
