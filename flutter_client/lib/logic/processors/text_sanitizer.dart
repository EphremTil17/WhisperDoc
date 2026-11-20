/// Client-side output sanitizer for transcription text.
///
/// Mirrors the backend's `Sanitizer.sanitize()` (security/sanitizer.py) to
/// neutralize ANSI escape sequences and control characters that could be
/// injected into terminals or focused applications via the clipboard/paste
/// automation path. Printable Unicode (accents, symbols, non-Latin scripts) is
/// preserved: it cannot drive a terminal, and stripping it corrupts dictation.
///
/// This is critical for the Groq Cloud path, which bypasses the backend
/// sanitizer entirely. On the backend path it is idempotent defense-in-depth.
class TextSanitizer {
  // ANSI CSI sequences (colors, cursor moves) and OSC title sequences.
  static final RegExp _ansiEscapeRegex = RegExp(
    r'\x1b\[[0-9;]*[mGKH]|\x1b\]0;.*?\x07',
  );

  // C0 controls (except \t \n \r), DEL, and C1 controls. ESC (\x1b) and the
  // 8-bit CSI introducer (\x9b) are covered, so any escape sequence the ANSI
  // pattern misses is still rendered inert.
  static final RegExp _controlCharRegex = RegExp(
    r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]',
  );

  /// Strips ANSI escapes and control characters from [text], then trims.
  static String sanitize(String text) => text
      .replaceAll(_ansiEscapeRegex, '')
      .replaceAll(_controlCharRegex, '')
      .trim();
}
