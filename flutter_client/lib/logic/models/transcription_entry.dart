/// Represents a single transcription event with field-level encryption.
class TranscriptionEntry {
  final int? id;
  final String encryptedText;
  final String ivBase64;
  final DateTime timestamp;
  final int? durationMs;
  final bool isIncognito;

  TranscriptionEntry({
    this.id,
    required this.encryptedText,
    required this.ivBase64,
    required this.timestamp,
    this.durationMs,
    this.isIncognito = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'encrypted_text': encryptedText,
      'iv_base64': ivBase64,
      'timestamp': timestamp.toIso8601String(),
      'duration_ms': durationMs,
      'is_incognito': isIncognito,
    };
  }

  factory TranscriptionEntry.fromJson(Map<String, dynamic> json) {
    return TranscriptionEntry(
      encryptedText: json['encrypted_text'] as String,
      ivBase64: json['iv_base64'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      durationMs: json['duration_ms'] as int?,
      isIncognito: json['is_incognito'] as bool? ?? false,
    );
  }
}
