/// Domain status representing the exact state of audio input hardware availability.
enum AudioInputStatus {
  /// Startup, pre-check state. Treated optimistically to permit recording checks.
  unknown,

  /// A usable audio input device is present (and matches the selected microphone if specified).
  available,

  /// Zero audio input devices are enumerated by the OS.
  noDevice,

  /// Audio input devices exist, but the saved target microphone ID is no longer
  /// present. Recording falls back to the system default device; Windows can
  /// reissue endpoint IDs (e.g. a USB mic moved to another port), so blocking
  /// here would strand users whose device is plugged in and working.
  selectedUnavailable,

  /// Operating system denied microphone permission.
  permissionDenied,
}

extension AudioInputStatusX on AudioInputStatus {
  /// Single source of truth for whether recording initialization can be attempted.
  bool get canRecord =>
      this == AudioInputStatus.available ||
      this == AudioInputStatus.unknown ||
      this == AudioInputStatus.selectedUnavailable;

  /// Whether recording should ignore the saved microphone and use the system
  /// default device.
  bool get usesDefaultDevice => this == AudioInputStatus.selectedUnavailable;

  /// Single source of truth for user-facing status copy.
  String? get bannerMessage => switch (this) {
    AudioInputStatus.noDevice =>
      'No microphone detected. Please connect an input device.',
    AudioInputStatus.selectedUnavailable =>
      'Selected microphone not found. Using the system default.',
    AudioInputStatus.permissionDenied =>
      'Microphone access is blocked. Enable it in your system settings.',
    AudioInputStatus.unknown || AudioInputStatus.available => null,
  };
}
