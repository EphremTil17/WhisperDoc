import 'package:characters/characters.dart';

/// Shows enough of a secret to recognise it, never enough to use it.
abstract final class SecretMask {
  static const int _shown = 4;

  /// Shorter secrets show no characters at all.
  static const int _minLengthToShow = 12;

  /// `gsk_…3f2a` for a long key, `••••` for a short one, '' for none.
  static String of(String? secret) {
    if (secret == null || secret.isEmpty) return '';
    final chars = secret.characters;
    if (chars.length < _minLengthToShow) return '••••';

    return '${chars.take(_shown)}…${chars.takeLast(_shown)}';
  }
}
