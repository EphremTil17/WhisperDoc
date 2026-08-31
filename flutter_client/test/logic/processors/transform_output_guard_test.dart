import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/logic/processors/text_sanitizer.dart';
import 'package:flutter_client/logic/processors/transform_output_guard.dart';

void main() {
  group('TransformOutputGuard', () {
    const defaultInput = 'This is a sample sentence for dictation testing.';

    test('returns null for empty or whitespace-only input', () {
      expect(TransformOutputGuard.normalize('Hello world', input: ''), isNull);
      expect(
        TransformOutputGuard.normalize('Hello world', input: '   '),
        isNull,
      );
    });

    test('returns null for empty or whitespace-only output', () {
      expect(TransformOutputGuard.normalize('', input: defaultInput), isNull);
      expect(
        TransformOutputGuard.normalize('   ', input: defaultInput),
        isNull,
      );
    });

    test('strips <think>...</think> reasoning blocks', () {
      const output = '''
<think>
The user dictated a sentence with filler words.
I will remove "um" and clean grammar.
</think>
This is the cleaned and polished sentence.
''';
      final result = TransformOutputGuard.normalize(
        output,
        input: defaultInput,
      );
      expect(result, 'This is the cleaned and polished sentence.');
      expect(result, isNot(contains('<think>')));
    });

    test('strips triple-backtick markdown code block fences', () {
      const output = '''
```markdown
This is the cleaned and polished sentence.
```
''';
      final result = TransformOutputGuard.normalize(
        output,
        input: defaultInput,
      );
      expect(result, 'This is the cleaned and polished sentence.');
    });

    test('strips enclosing double and single quotes', () {
      expect(
        TransformOutputGuard.normalize(
          '"This is the cleaned sentence for testing."',
          input: defaultInput,
        ),
        'This is the cleaned sentence for testing.',
      );

      expect(
        TransformOutputGuard.normalize(
          "'This is the cleaned sentence for testing.'",
          input: defaultInput,
        ),
        'This is the cleaned sentence for testing.',
      );

      expect(
        TransformOutputGuard.normalize(
          '“This is the cleaned sentence for testing.”',
          input: defaultInput,
        ),
        'This is the cleaned sentence for testing.',
      );

      expect(
        TransformOutputGuard.normalize(
          '‘This is the cleaned sentence for testing.’',
          input: defaultInput,
        ),
        'This is the cleaned sentence for testing.',
      );
    });

    test('normalizes typographic punctuation to ASCII before TextSanitizer', () {
      // Chat models emit curly quotes: "don’t" with \u2019
      const output = 'They don’t know what they’re doing — it’s a test… right?';
      final guarded = TransformOutputGuard.normalize(
        output,
        input: 'They do not know what they are doing. It is a test right?',
      );

      expect(guarded, isNotNull);
      final containsDont = contains("don't");
      final containsTheyre = contains("they're");
      final containsIts = contains("it's");

      // Verify straight apostrophe and hyphen
      expect(guarded, containsDont);
      expect(guarded, containsTheyre);
      expect(guarded, containsIts);
      expect(guarded, contains('-'));
      expect(guarded, contains('...'));

      // Crucial integration check: TextSanitizer must NOT strip the normalized apostrophes!
      final guardedText = guarded;
      if (guardedText == null) {
        fail('guarded output must not be null');
      }
      final sanitized = TextSanitizer.sanitize(guardedText);
      expect(sanitized, containsDont);
      expect(sanitized, containsTheyre);
      expect(sanitized, containsIts);
    });

    test('rejects outputs below minimum length ratio (< 0.3)', () {
      const longInput =
          'This is a fairly lengthy transcription of a user dictating multiple points about system architecture and requirements.';
      const shortOutput = 'Too short.';

      final result = TransformOutputGuard.normalize(
        shortOutput,
        input: longInput,
      );
      expect(result, isNull);
    });

    test('rejects outputs above maximum length ratio (> 4.5)', () {
      const repeatCount = 10;
      const shortInput = 'Fix this bug.';
      final longOutput =
          'Here is an extremely verbose explanation and ' * repeatCount;

      final result = TransformOutputGuard.normalize(
        longOutput,
        input: shortInput,
      );
      expect(result, isNull);
    });
  });
}
