import 'dart:async';

/// Processor for analyzing audio signal properties.
///
/// Provides heuristic checks for signal quality, such as silence detection.
class AudioSignalProcessor {
  /// Detects if an audio stream is "dead silent" over a given duration.
  ///
  /// Monitors the [stream] of amplitude values (0.0 to 1.0).
  /// Returns [true] if the peak amplitude remains below [threshold]
  /// for the entire [timeout] duration.
  Future<bool> detectSilence(
    Stream<double> stream, {
    Duration timeout = const Duration(seconds: 3),
    double threshold = 0.00000001, // Near-zero to allow for analog noise floors
  }) async {
    double peakSeen = 0.0;

    // Create a subscription to the amplitude stream
    final subscription = stream.listen((amplitude) {
      if (amplitude > peakSeen) {
        peakSeen = amplitude;
      }
    });

    // Wait for the heuristic window
    await Future.delayed(timeout);

    // Cleanup
    await subscription.cancel();

    // If peak is still essentially zero, it's a silent/virtual driver
    return peakSeen <= threshold;
  }
}
