import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:flutter_client/services/utility/logging_service.dart';

class ClipboardService {
  // UTF-16 encodes each code unit as 2 bytes; +1 for the null terminator.
  static const _utf16BytesPerUnit = 2;
  static const _clipboardRetryCount = 5;
  static const _clipboardRetryDelayMs = 50;

  // Win32 SendInput: we send exactly 4 keyboard events (CtrlDn, VDn, VUp, CtrlUp).
  static const _inputEventCount = 4;
  static const _vDownIndex = 1;
  static const _vUpIndex = 2;
  static const _ctrlUpIndex = 3;

  static Future<void> copyToClipboard(String text) async {
    if (text.isEmpty) return;

    // Use Win32 API directly for reliability
    final units = text.codeUnits;
    final size =
        (units.length + 1) * _utf16BytesPerUnit; // UTF-16 + null terminator

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
    for (var i = 0; i < _clipboardRetryCount; i++) {
      if (OpenClipboard(0) != 0) {
        EmptyClipboard();
        // win32 v5.x SetClipboardData expects int (handle address), not Pointer
        SetClipboardData(CF_UNICODETEXT, hMem.address);
        CloseClipboard();
        success = true;
        break;
      }
      await Future.delayed(
        const Duration(milliseconds: _clipboardRetryDelayMs),
      );
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

    final inputs = calloc<INPUT>(_inputEventCount);
    try {
      // Use scan codes to bypass Flutter's virtual key tracking
      // Ctrl scan code: 0x1D, V scan code: 0x2F
      const ctrlScanCode = 0x1D;
      const vScanCode = 0x2F;

      final ctrlDown = inputs + 0;
      final vDown = inputs + _vDownIndex;
      final vUp = inputs + _vUpIndex;
      final ctrlUp = inputs + _ctrlUpIndex;

      final ctrlDownInput = ctrlDown.ref;
      final vDownInput = vDown.ref;
      final vUpInput = vUp.ref;
      final ctrlUpInput = ctrlUp.ref;

      // Ctrl Down
      ctrlDownInput.type = INPUT_KEYBOARD;
      ctrlDownInput.ki.wScan = ctrlScanCode;
      ctrlDownInput.ki.dwFlags = KEYEVENTF_SCANCODE;

      // V Down
      vDownInput.type = INPUT_KEYBOARD;
      vDownInput.ki.wScan = vScanCode;
      vDownInput.ki.dwFlags = KEYEVENTF_SCANCODE;

      // V Up
      vUpInput.type = INPUT_KEYBOARD;
      vUpInput.ki.wScan = vScanCode;
      vUpInput.ki.dwFlags = KEYEVENTF_SCANCODE | KEYEVENTF_KEYUP;

      // Ctrl Up
      ctrlUpInput.type = INPUT_KEYBOARD;
      ctrlUpInput.ki.wScan = ctrlScanCode;
      ctrlUpInput.ki.dwFlags = KEYEVENTF_SCANCODE | KEYEVENTF_KEYUP;

      // Send all inputs at once for atomicity
      SendInput(_inputEventCount, inputs, sizeOf<INPUT>());

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
