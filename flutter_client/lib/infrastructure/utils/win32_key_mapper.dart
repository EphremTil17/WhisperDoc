import 'package:flutter/services.dart';

/// Utility class to handle mapping between Flutter's LogicalKeyboardKey
/// and Win32 virtual key codes (V-Keys).
class Win32KeyMapper {
  /// Maps a Flutter LogicalKeyboardKey to its corresponding Win32 virtual key code (V-Key).
  ///
  /// Returns the V-Key integer if a mapping exists, or null otherwise.
  static int? mapToWin32VKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.keyA) return 0x41;
    if (key == LogicalKeyboardKey.keyB) return 0x42;
    if (key == LogicalKeyboardKey.keyC) return 0x43;
    if (key == LogicalKeyboardKey.keyD) return 0x44;
    if (key == LogicalKeyboardKey.keyE) return 0x45;
    if (key == LogicalKeyboardKey.keyF) return 0x46;
    if (key == LogicalKeyboardKey.keyG) return 0x47;
    if (key == LogicalKeyboardKey.keyH) return 0x48;
    if (key == LogicalKeyboardKey.keyI) return 0x49;
    if (key == LogicalKeyboardKey.keyJ) return 0x4A;
    if (key == LogicalKeyboardKey.keyK) return 0x4B;
    if (key == LogicalKeyboardKey.keyL) return 0x4C;
    if (key == LogicalKeyboardKey.keyM) return 0x4D;
    if (key == LogicalKeyboardKey.keyN) return 0x4E;
    if (key == LogicalKeyboardKey.keyO) return 0x4F;
    if (key == LogicalKeyboardKey.keyP) return 0x50;
    if (key == LogicalKeyboardKey.keyQ) return 0x51;
    if (key == LogicalKeyboardKey.keyR) return 0x52;
    if (key == LogicalKeyboardKey.keyS) return 0x53;
    if (key == LogicalKeyboardKey.keyT) return 0x54;
    if (key == LogicalKeyboardKey.keyU) return 0x55;
    if (key == LogicalKeyboardKey.keyV) return 0x56;
    if (key == LogicalKeyboardKey.keyW) return 0x57;
    if (key == LogicalKeyboardKey.keyX) return 0x58;
    if (key == LogicalKeyboardKey.keyY) return 0x59;
    if (key == LogicalKeyboardKey.keyZ) return 0x5A;

    if (key == LogicalKeyboardKey.f1) return 0x70;
    if (key == LogicalKeyboardKey.f2) return 0x71;
    if (key == LogicalKeyboardKey.f3) return 0x72;
    if (key == LogicalKeyboardKey.f4) return 0x73;
    if (key == LogicalKeyboardKey.f5) return 0x74;
    if (key == LogicalKeyboardKey.f6) return 0x75;
    if (key == LogicalKeyboardKey.f7) return 0x76;
    if (key == LogicalKeyboardKey.f8) return 0x77;
    if (key == LogicalKeyboardKey.f9) return 0x78;
    if (key == LogicalKeyboardKey.f10) return 0x79;
    if (key == LogicalKeyboardKey.f11) return 0x7A;
    if (key == LogicalKeyboardKey.f12) return 0x7B;

    return null;
  }
}
