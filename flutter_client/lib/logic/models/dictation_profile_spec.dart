/// Contract defining any entity that can act as an active dictation profile.
/// Implemented by both built-in [DictationProfile] and user-defined [CustomProfile].
abstract interface class DictationProfileSpec {
  /// Stable persistence key (`raw`, `clean`, ..., `custom1`, `custom2`, `custom3`).
  String get storageKey;

  /// Display label shown on the action button and menu tile.
  String get label;

  /// Fully composed system prompt, or null when no LLM call is needed.
  String? get systemPrompt;

  /// Whether this profile requires calling the post-processing LLM.
  bool get requiresLlm;

  /// Whether the output is pasted with its line breaks. Styles that write a
  /// single passage paste on one line, so a stray line break can't submit
  /// whatever came before it in a terminal.
  bool get keepsLineBreaks;

  /// Whether the user may edit or delete this profile.
  bool get isEditable;
}
