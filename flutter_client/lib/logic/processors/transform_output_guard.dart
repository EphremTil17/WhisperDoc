import 'package:characters/characters.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';

/// Context-blind static processor that cleans, normalizes, and validates
/// LLM post-processing output before passing it to [TextSanitizer].
class TransformOutputGuard {
  static final RegExp _thinkTagRegex = RegExp(
    r'<think>[\s\S]*?<\/think>',
    caseSensitive: false,
  );

  static final RegExp _codeFenceRegex = RegExp(
    r'^```[a-zA-Z0-9_-]*\s*([\s\S]*?)\s*```$',
  );

  static final RegExp _singleQuoteVariants = RegExp(
    r'[\u2018\u2019\u201A\u201B]',
  );

  static final RegExp _doubleQuoteVariants = RegExp(
    r'[\u201C\u201D\u201E\u201F]',
  );

  static const int _minWrappedQuoteLength = 2;

  static final RegExp _dashVariants = RegExp(r'[\u2013\u2014\u2015]');

  /// Cleans and validates [rawOutput] against [input].
  ///
  /// Returns the cleaned string if valid, or `null` if the output should be
  /// rejected (e.g. empty, hallucination, truncation, or severe length divergence).
  static String? normalize(String rawOutput, {required String input}) {
    final trimmedInput = input.trim();
    if (trimmedInput.isEmpty) return null;

    // 1. Strip any <think>...</think> chain-of-thought blocks.
    var cleaned = rawOutput.replaceAll(_thinkTagRegex, '').trim();

    if (cleaned.isEmpty) return null;

    // 2. Strip one wrapping pair of markdown code fences or enclosing quotes.
    cleaned = _stripEnclosingWrappers(cleaned);

    if (cleaned.isEmpty) return null;

    // 3. Typographic normalization to ASCII equivalents before TextSanitizer.
    cleaned = cleaned
        .replaceAll(_singleQuoteVariants, "'")
        .replaceAll(_doubleQuoteVariants, '"')
        .replaceAll(_dashVariants, '-')
        .replaceAll('\u2026', '...')
        .replaceAll('\u00A0', ' ')
        .trim();

    if (cleaned.isEmpty) return null;

    // 4. Sanity length ratio check relative to input length.
    final inputLen = trimmedInput.length;
    final outputLen = cleaned.length;
    final ratio = outputLen / inputLen;

    if (ratio < AppConstants.groqTransformMinLengthRatio ||
        ratio > AppConstants.groqTransformMaxLengthRatio) {
      return null;
    }

    return cleaned;
  }

  static String _stripEnclosingWrappers(String text) {
    var s = text.trim();
    if (s.isEmpty) return s;

    // Strip enclosing code block fence ```...```
    final fenceMatch = _codeFenceRegex.firstMatch(s);
    if (fenceMatch != null) {
      s = (fenceMatch.group(1) ?? '').trim();
    }

    // Strip single pair of wrapping quotes covering the entire output
    final chars = s.characters;
    if (chars.length >= _minWrappedQuoteLength) {
      final first = chars.first;
      final last = chars.last;
      if ((first == '"' && last == '"') ||
          (first == "'" && last == "'") ||
          (first == '“' && last == '”') ||
          (first == '‘' && last == '’')) {
        s = chars.getRange(1, chars.length - 1).string.trim();
      }
    }

    return s;
  }
}
