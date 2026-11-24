/// OpenRouter model ids: `author/slug`, as its API lists them.
abstract final class OpenRouterModelId {
  /// Each part starts with a letter, digit or underscore; anything else is
  /// not used, so a tampered cache or a typo can't steer a request path (no
  /// `..` segment).
  static final RegExp _pattern = RegExp(r'^[a-z0-9][\w.-]*/\w[\w.:-]*$');

  static bool isValid(String id) => _pattern.hasMatch(id);
}
