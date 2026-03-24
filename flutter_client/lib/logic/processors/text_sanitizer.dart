/// Client-side output sanitizer for transcription text.
///
/// Mirrors the backend's `Sanitizer.sanitize()` (security/sanitizer.py) to
/// neutralize control characters, ANSI escape sequences, and non-printable
/// characters that could be injected into terminals or focused applications
/// via the clipboard/paste automation path.
///
/// This is critical for the Groq Cloud path which bypasses the backend
/// sanitizer entirely. The backend path is already sanitized server-side,
/// but applying this client-side is harmless (idempotent on clean text)
/// and provides defense-in-depth.
class TextSanitizer {
  // ANSI CSI sequences (colors, cursor moves) and OSC title sequences.
  static final RegExp _ansiEscapeRegex = RegExp(
    r'\x1b\[[0-9;]*[mGKH]|\x1b\]0;.*?\x07',
  );

  // Whitelist: printable ASCII (\x20-\x7E) + safe whitespace (\n, \r, \t).
  // Everything else (ANSI \x1b, null \x00, other control chars < \x20) is stripped.
  static final RegExp _nonPrintableRegex = RegExp(
    r'[^\x20-\x7E\n\r\t]',
  );

  /// Strips ANSI escapes and non-printable characters from [text].
  ///
  /// Returns empty string on null/empty input or if sanitization fails
  /// (fail-secure). Idempotent on already-clean text.
  static String sanitize(String text) {
    if (text.isEmpty) return '';

    try {
      // 1. Strip ANSI escape sequences explicitly.
      var cleaned = text.replaceAll(_ansiEscapeRegex, '');

      // 2. Apply strict whitelist (printable ASCII + safe whitespace).
      cleaned = cleaned.replaceAll(_nonPrintableRegex, '');

      // 3. Final trim.
      return cleaned.trim();
    } catch (_) {
      // Fail-secure: return empty if processing fails.
      return '';
    }
  }
}
