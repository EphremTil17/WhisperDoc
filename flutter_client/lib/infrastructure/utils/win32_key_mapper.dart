import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

/// Utility class to handle mapping between Flutter's LogicalKeyboardKey
/// and Win32 virtual key codes (V-Keys).
abstract final class Win32KeyMapper {
  static final Map<LogicalKeyboardKey, int> _logicalKeyToVirtualKey = {
    LogicalKeyboardKey.keyA: VK_A,
    LogicalKeyboardKey.keyB: VK_B,
    LogicalKeyboardKey.keyC: VK_C,
    LogicalKeyboardKey.keyD: VK_D,
    LogicalKeyboardKey.keyE: VK_E,
    LogicalKeyboardKey.keyF: VK_F,
    LogicalKeyboardKey.keyG: VK_G,
    LogicalKeyboardKey.keyH: VK_H,
    LogicalKeyboardKey.keyI: VK_I,
    LogicalKeyboardKey.keyJ: VK_J,
    LogicalKeyboardKey.keyK: VK_K,
    LogicalKeyboardKey.keyL: VK_L,
    LogicalKeyboardKey.keyM: VK_M,
    LogicalKeyboardKey.keyN: VK_N,
    LogicalKeyboardKey.keyO: VK_O,
    LogicalKeyboardKey.keyP: VK_P,
    LogicalKeyboardKey.keyQ: VK_Q,
    LogicalKeyboardKey.keyR: VK_R,
    LogicalKeyboardKey.keyS: VK_S,
    LogicalKeyboardKey.keyT: VK_T,
    LogicalKeyboardKey.keyU: VK_U,
    LogicalKeyboardKey.keyV: VK_V,
    LogicalKeyboardKey.keyW: VK_W,
    LogicalKeyboardKey.keyX: VK_X,
    LogicalKeyboardKey.keyY: VK_Y,
    LogicalKeyboardKey.keyZ: VK_Z,
    LogicalKeyboardKey.f1: VK_F1,
    LogicalKeyboardKey.f2: VK_F2,
    LogicalKeyboardKey.f3: VK_F3,
    LogicalKeyboardKey.f4: VK_F4,
    LogicalKeyboardKey.f5: VK_F5,
    LogicalKeyboardKey.f6: VK_F6,
    LogicalKeyboardKey.f7: VK_F7,
    LogicalKeyboardKey.f8: VK_F8,
    LogicalKeyboardKey.f9: VK_F9,
    LogicalKeyboardKey.f10: VK_F10,
    LogicalKeyboardKey.f11: VK_F11,
    LogicalKeyboardKey.f12: VK_F12,
  };

  /// Maps a Flutter LogicalKeyboardKey to its corresponding Win32 virtual key code (V-Key).
  ///
  /// Returns the V-Key integer if a mapping exists, or null otherwise.
  static int? mapToWin32VKey(LogicalKeyboardKey key) =>
      _logicalKeyToVirtualKey[key];
}
