import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:flutter/services.dart';
import 'package:flutter_client/services/utility/logging_service.dart';

/// Ultra-lightweight native Windows audio service.
/// Plays custom chimes from memory using the win32 PlaySound API.
/// This is the leanest possible approach: No heavy plugins, zero disk I/O at playback.
class AudioCueService {
  static final _chimeFlags = SND_MEMORY | SND_ASYNC | SND_NODEFAULT;
  static final _fallbackFlags = SND_ALIAS | SND_ASYNC | SND_NODEFAULT;

  // Allocated once and kept for the process lifetime: with SND_ASYNC,
  // PlaySound may still read the alias after it returns.
  static final PCWSTR _startFallback = 'SystemAsterisk'.toPcwstr();
  static final PCWSTR _stopFallback = 'SystemDefault'.toPcwstr();

  final LoggingService _logger = LoggingService();

  Pointer<Uint8>? _startSoundPtr;
  Pointer<Uint8>? _stopSoundPtr;
  bool _isInitialized = false;

  /// Loads custom audio assets into native memory for instant playback.
  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      _startSoundPtr = await _loadAssetToNativeMemory('assets/audio/start.wav');
      _stopSoundPtr = await _loadAssetToNativeMemory('assets/audio/stop.wav');
      _isInitialized = true;
      _logger.info(
        'AudioCueService: Custom native chimes preloaded into memory',
      );
    } catch (e) {
      _logger.warning(
        'AudioCueService: Failed to preload chimes ($e). System sounds fallback will be used.',
      );
    }
  }

  /// Plays the start chime with near-zero latency.
  void playStartCue() {
    final startPtr = _startSoundPtr;
    if (_isInitialized && startPtr != null) {
      PlaySound(PCWSTR(startPtr.cast()), null, _chimeFlags);
    } else {
      // Fallback to a subtle system sound if assets are missing
      PlaySound(_startFallback, null, _fallbackFlags);
    }
  }

  /// Plays the stop chime with near-zero latency.
  void playStopCue() {
    final stopPtr = _stopSoundPtr;
    if (_isInitialized && stopPtr != null) {
      PlaySound(PCWSTR(stopPtr.cast()), null, _chimeFlags);
    } else {
      PlaySound(_stopFallback, null, _fallbackFlags);
    }
  }

  void dispose() {
    final startPtr = _startSoundPtr;
    if (startPtr != null) calloc.free(startPtr);
    final stopPtr = _stopSoundPtr;
    if (stopPtr != null) calloc.free(stopPtr);
  }

  Future<Pointer<Uint8>?> _loadAssetToNativeMemory(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();

      // Allocate native memory that persists for the app lifetime
      final ptr = calloc<Uint8>(bytes.length);
      ptr.asTypedList(bytes.length).setAll(0, bytes);

      return ptr;
    } catch (_) {
      return null;
    }
  }
}
