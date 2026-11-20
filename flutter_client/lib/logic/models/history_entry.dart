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
}
