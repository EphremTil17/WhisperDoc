/// Represents a single transcription event.
class TranscriptionEntry {
  final String text;
  final DateTime timestamp;
  final Duration? duration;
  final bool isIncognito;

  const TranscriptionEntry({
    required this.text,
    required this.timestamp,
    this.duration,
    this.isIncognito = false,
  });

  // For future JSON serialization
  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'duration_ms': duration?.inMilliseconds,
      'is_incognito': isIncognito,
    };
  }

  factory TranscriptionEntry.fromJson(Map<String, dynamic> json) {
    return TranscriptionEntry(
      text: json['text'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      duration: json['duration_ms'] != null
          ? Duration(milliseconds: json['duration_ms'] as int)
          : null,
      isIncognito: json['is_incognito'] as bool? ?? false,
    );
  }
}
