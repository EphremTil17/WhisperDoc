import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/logic/processors/text_sanitizer.dart';

void main() {
  group('TextSanitizer', () {
    test('returns empty string for empty input', () {
      expect(TextSanitizer.sanitize(''), '');
    });

    test('passes through clean ASCII text unchanged', () {
      expect(TextSanitizer.sanitize('Hello world'), 'Hello world');
    });

    test('preserves safe whitespace (newlines, tabs)', () {
      expect(TextSanitizer.sanitize('line1\nline2\ttab'), 'line1\nline2\ttab');
    });

    test('strips ANSI color sequences', () {
      expect(TextSanitizer.sanitize('\x1b[31mred text\x1b[0m'), 'red text');
    });

    test('strips ANSI cursor movement sequences', () {
      expect(TextSanitizer.sanitize('\x1b[2Kmoved\x1b[H'), 'moved');
    });

    test('strips OSC title sequences', () {
      expect(
        TextSanitizer.sanitize('\x1b]0;malicious title\x07safe text'),
        'safe text',
      );
    });

    test('strips null bytes', () {
      expect(TextSanitizer.sanitize('hello\x00world'), 'helloworld');
    });

    test('strips control characters below 0x20', () {
      // \x01 (SOH), \x02 (STX), \x03 (ETX), \x07 (BEL)
      expect(TextSanitizer.sanitize('a\x01b\x02c\x03d\x07e'), 'abcde');
    });

    test('strips escape character without valid sequence', () {
      expect(TextSanitizer.sanitize('before\x1bafter'), 'beforeafter');
    });

    test('trims leading and trailing whitespace', () {
      expect(TextSanitizer.sanitize('  hello  '), 'hello');
    });

    test('is idempotent on already-clean text', () {
      const clean = 'This is already clean text.';
      expect(TextSanitizer.sanitize(TextSanitizer.sanitize(clean)), clean);
    });

    test('handles mixed ANSI and control characters', () {
      expect(
        TextSanitizer.sanitize('\x1b[32m\x00safe\x01 text\x1b[0m'),
        'safe text',
      );
    });
  });
}
