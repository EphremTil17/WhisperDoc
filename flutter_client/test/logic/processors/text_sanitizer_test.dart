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

    test('preserves printable Unicode in dictated text', () {
      const samples = [
        'José ordered a café au lait',
        'naïve résumé — “quoted”',
        'It costs €20 at 25°C',
        'Ünïcödé Ελληνικά 日本語',
      ];
      for (final text in samples) {
        expect(TextSanitizer.sanitize(text), text);
      }
    });

    test('strips C1 controls including the 8-bit CSI introducer', () {
      expect(TextSanitizer.sanitize('c1\x9b31m csi'), 'c131m csi');
    });

    test('handles mixed ANSI and control characters', () {
      expect(
        TextSanitizer.sanitize('\x1b[32m\x00safe\x01 text\x1b[0m'),
        'safe text',
      );
    });

    test('strips any CSI sequence, such as a screen clear', () {
      expect(TextSanitizer.sanitize('a\x1b[2Jb\x1b[?25lc'), 'abc');
    });

    test('strips OSC sequences ended by ST, such as hyperlinks', () {
      expect(
        TextSanitizer.sanitize(
          '\x1b]8;;https://x.test\x1b\\link\x1b]8;;\x1b\\',
        ),
        'link',
      );
    });

    test('strips bidi overrides and isolates (Trojan Source)', () {
      expect(
        TextSanitizer.sanitize('rm \u202eexe.txt\u2066 \u2069done'),
        'rm exe.txt done',
      );
    });

    test('keeps the joiners real scripts and emoji need', () {
      const joined = 'می\u200cخواهم \u{1F469}\u200d\u{1F4BB}';
      expect(TextSanitizer.sanitize(joined), joined);
    });
  });
}
