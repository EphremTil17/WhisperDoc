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

    test('a back-off blocks requests until it has passed', () {
      limiter.backOff(const Duration(seconds: retryAfterSeconds));

      expect(limiter.canRequest(), isFalse);
      expect(
        limiter.retryAfter.inSeconds,
        inInclusiveRange(retryAfterMinusOne, retryAfterSeconds),
      );
    });

    test('an elapsed back-off allows requests again', () {
      limiter.backOff(Duration.zero);

      expect(limiter.canRequest(), isTrue);
      expect(limiter.retryAfter, Duration.zero);
    });
  });
}
