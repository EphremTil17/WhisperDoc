// ignore_for_file: avoid-late-keyword
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/services/transcription/groq_rate_limiter.dart';

void main() {
  // Named constants used across rate-limiter tests.
  const rpmWindowRequests = 20;
  const retryAfterSeconds = 30;
  const retryAfterMinusOne =
      retryAfterSeconds - 1; // greaterThanOrEqualTo bound

  group('GroqRateLimiter', () {
    late GroqRateLimiter limiter;

    setUp(() {
      limiter = GroqRateLimiter();
    });

    test('allows requests when fresh', () {
      expect(limiter.canRequest(), isTrue);
    });

    test('tracks requests in RPM window', () {
      for (var i = 0; i < rpmWindowRequests; i++) {
        expect(limiter.canRequest(), isTrue);
        limiter.recordRequest();
      }
      // 20th request fills the window
      expect(limiter.canRequest(), isFalse);
    });

    test('retryAfter is zero when no 429 received', () {
      expect(limiter.retryAfter, Duration.zero);
    });

    test('parses retry-after header and blocks requests', () {
      limiter.updateFromHeaders({'retry-after': '$retryAfterSeconds'});

      expect(limiter.canRequest(), isFalse);
      expect(
        limiter.retryAfter.inSeconds,
        greaterThanOrEqualTo(retryAfterMinusOne),
      );
    });

    test('ignores malformed retry-after header', () {
      limiter.updateFromHeaders({'retry-after': 'not-a-number'});

      expect(limiter.canRequest(), isTrue);
    });

    test('statusMessage reports current counts', () {
      limiter.recordRequest();
      limiter.recordRequest();

      final status = limiter.statusMessage;
      expect(status, contains('2/20 RPM'));
      expect(status, contains('2/2000 RPD'));
    });
  });
}
