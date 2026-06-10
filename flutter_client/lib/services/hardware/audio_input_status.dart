/// Domain status representing the exact state of audio input hardware availability.
enum AudioInputStatus {
  /// Startup, pre-check state. Treated optimistically to permit recording checks.
  unknown,

  /// A usable audio input device is present (and matches the selected microphone if specified).
  available,

  /// Zero audio input devices are enumerated by the OS.
  noDevice,

  /// Audio input devices exist, but the saved target microphone ID is no longer present.
  selectedUnavailable,

  /// Operating system denied microphone permission.
  permissionDenied,
}

extension AudioInputStatusX on AudioInputStatus {
  /// Single source of truth for whether recording initialization can be attempted.
  bool get canRecord =>
      this == AudioInputStatus.available || this == AudioInputStatus.unknown;

  /// Single source of truth for user-facing status copy.
  String? get bannerMessage => switch (this) {
        AudioInputStatus.noDevice =>
          'No microphone detected. Please connect an input device.',
        AudioInputStatus.selectedUnavailable =>
          'Your selected microphone is unavailable. Connect it or pick another in Settings.',
        AudioInputStatus.permissionDenied =>
          'Microphone access is blocked. Enable it in your system settings.',
        AudioInputStatus.unknown || AudioInputStatus.available => null,
      };
}
