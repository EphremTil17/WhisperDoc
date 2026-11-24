/// Where a dictation is transcribed: the user's own WhisperDoc server, or a
/// cloud service called directly with the user's own API key.
enum TranscriptionSource {
  /// The user's WhisperDoc server, over its WebSocket.
  server('backend', 'WhisperDoc server'),

  /// Groq's Whisper API.
  groq('groq', 'Groq'),

  /// OpenRouter: any speech-to-text model it serves, with zero data
  /// retention enforced by default.
  openRouter('openrouter', 'OpenRouter');

  const TranscriptionSource(this.storageKey, this.label);

  /// Persisted value. `backend` and `groq` predate OpenRouter, so settings
  /// saved by earlier versions load unchanged.
  final String storageKey;

  /// The service's name in the UI and in messages.
  final String label;

  /// Called over HTTPS with the user's key: audio is buffered and uploaded
  /// when the recording stops, and the output styles can run.
  bool get isCloud => this != server;

  /// The stored source, or the server for anything unknown.
  static TranscriptionSource fromStorageKey(String? key) {
    for (final source in values) {
      if (source.storageKey == key) return source;
    }

    return server;
  }
}
