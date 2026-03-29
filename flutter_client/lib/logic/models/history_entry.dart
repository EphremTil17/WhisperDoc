/// Represents a single encrypted history item persisted by the app.
class HistoryEntry {
  final int? id;
  final String encryptedText;
  final String ivBase64;
  final DateTime timestamp;
  final int? durationMs;
  final bool isIncognito;

  HistoryEntry({
    this.id,
    required this.encryptedText,
    required this.ivBase64,
    required this.timestamp,
    this.durationMs,
    this.isIncognito = false,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      encryptedText: json['encrypted_text'] as String,
      ivBase64: json['iv_base64'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      durationMs: json['duration_ms'] as int?,
      isIncognito: json['is_incognito'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'encrypted_text': encryptedText,
      'iv_base64': ivBase64,
      'timestamp': timestamp.toIso8601String(),
      'duration_ms': durationMs,
      'is_incognito': isIncognito,
    };
  }
}
