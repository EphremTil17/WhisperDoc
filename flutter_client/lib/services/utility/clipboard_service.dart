import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:flutter_client/services/utility/logging_service.dart';

class ClipboardService {
  static final LoggingService _logger = LoggingService();

  // UTF-16 encodes each code unit as 2 bytes; +1 for the null terminator.
  static const _utf16BytesPerUnit = 2;
  static const _clipboardRetryCount = 5;
  static const _clipboardRetryDelayMs = 50;

  // Win32 SendInput: we send exactly 4 keyboard events (CtrlDn, VDn, VUp, CtrlUp).
  static const _inputEventCount = 4;
  static const _vDownIndex = 1;
  static const _vUpIndex = 2;
  static const _ctrlUpIndex = 3;

  /// Formats Windows reads to keep a copy out of clipboard history (Win+V)
  /// and cloud clipboard sync. The first excludes it by being present; the
  /// other two say "no" outright (a zero DWORD) to apps that read them.
  static const _privateFormats = [
    'ExcludeClipboardContentFromMonitorProcessing',
    'CanIncludeInClipboardHistory',
    'CanUploadToCloudClipboard',
  ];

  /// Places [text] on the clipboard. Returns whether it actually landed there,
  /// so callers never paste stale clipboard contents after a failed copy.
  /// A [private] copy (incognito) stays out of clipboard history and sync.
  static Future<bool> copyToClipboard(
    String text, {
    bool private = false,
  }) async {
    if (text.isEmpty) return false;

    // Use Win32 API directly for reliability
    final units = text.codeUnits;
    final size =
        (units.length + 1) * _utf16BytesPerUnit; // UTF-16 + null terminator

    final hMem = GlobalAlloc(GMEM_MOVEABLE, size).value;
    if (hMem.isNull) return false;

    final pMem = GlobalLock(hMem).value;
    if (pMem.isNull) {
      GlobalFree(hMem);

      return false;
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
      if (OpenClipboard(null).value) {
        EmptyClipboard();
        // On success the system owns hMem; on failure it is still ours.
        success = !SetClipboardData(CF_UNICODETEXT, HANDLE(hMem)).value.isNull;
        if (success && private) _markPrivate();
        CloseClipboard();
        break;
      }
      await Future.delayed(
        const Duration(milliseconds: _clipboardRetryDelayMs),
      );
    }

    if (success) {
      _logger.info('Text copied to clipboard (Win32)');
    } else {
      GlobalFree(hMem);
      _logger.error('Failed to set clipboard');
    }

    return success;
  }

  /// Adds [_privateFormats] to the open clipboard. Each carries a zero DWORD;
  /// the system owns a block once set, so only a refused one is freed here.
  static void _markPrivate() {
    var marked = 0;
    for (final name in _privateFormats) {
      final format = using(
        (arena) => RegisterClipboardFormat(arena.pcwstr(name)).value,
      );
      if (format == 0) continue;

      final hMem = GlobalAlloc(GMEM_MOVEABLE, sizeOf<Uint32>()).value;
      if (hMem.isNull) continue;
      final pMem = GlobalLock(hMem).value;
      if (pMem.isNull) {
        GlobalFree(hMem);
        continue;
      }
      pMem.cast<Uint32>().value = 0;
      GlobalUnlock(hMem);

      if (SetClipboardData(format, HANDLE(hMem)).value.isNull) {
        GlobalFree(hMem);
      } else {
        marked++;
      }
    }
    if (marked < _privateFormats.length) {
      _logger.warning(
        'Incognito copy marked $marked of ${_privateFormats.length} '
        'private formats; it may appear in clipboard history',
      );
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
      _logger.info('Skipping paste simulation (WhisperDoc is focused)');

      return;
    }

    _logger.info('Simulating Ctrl+V via SendInput (scan codes)...');

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

      _logger.info('Paste simulation complete');
    } catch (e) {
      _logger.error('Paste simulation failed: $e');
    } finally {
      free(inputs);
    }
  }
}
