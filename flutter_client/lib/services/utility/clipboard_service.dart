import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:flutter_client/services/utility/logging_service.dart';

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

  /// Simulates Ctrl+V on Windows using scan codes to avoid Flutter's
  /// HardwareKeyboard intercepting the events and causing state conflicts.
  /// Skips simulation if WhisperDoc itself is the foreground window.
  static Future<void> simulatePaste() async {
    // Check if our app is the foreground window - if so, skip paste
    // to avoid keyboard state conflicts with Flutter
    final ourWindow = GetActiveWindow();
    final foregroundWindow = GetForegroundWindow();

    if (ourWindow == foregroundWindow) {
      LoggingService().info(
        'Skipping paste simulation (WhisperDoc is focused)',
        sendToServer: false,
      );
      return;
    }

    LoggingService().info(
      'Simulating Ctrl+V via SendInput (scan codes)...',
      sendToServer: false,
    );

    final inputs = calloc<INPUT>(4);
    try {
      // Use scan codes to bypass Flutter's virtual key tracking
      // Ctrl scan code: 0x1D, V scan code: 0x2F
      const ctrlScanCode = 0x1D;
      const vScanCode = 0x2F;

      // Ctrl Down
      inputs[0].type = INPUT_KEYBOARD;
      inputs[0].ki.wScan = ctrlScanCode;
      inputs[0].ki.dwFlags = KEYEVENTF_SCANCODE;

      // V Down
      inputs[1].type = INPUT_KEYBOARD;
      inputs[1].ki.wScan = vScanCode;
      inputs[1].ki.dwFlags = KEYEVENTF_SCANCODE;

      // V Up
      inputs[2].type = INPUT_KEYBOARD;
      inputs[2].ki.wScan = vScanCode;
      inputs[2].ki.dwFlags = KEYEVENTF_SCANCODE | KEYEVENTF_KEYUP;

      // Ctrl Up
      inputs[3].type = INPUT_KEYBOARD;
      inputs[3].ki.wScan = ctrlScanCode;
      inputs[3].ki.dwFlags = KEYEVENTF_SCANCODE | KEYEVENTF_KEYUP;

      // Send all 4 inputs at once for atomicity
      SendInput(4, inputs, sizeOf<INPUT>());

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
