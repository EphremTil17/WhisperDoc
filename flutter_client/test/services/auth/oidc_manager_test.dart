import 'package:flutter_client/services/auth/oidc_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OidcManager.summarizeErrorBody', () {
    test('extracts OAuth error and description from JSON', () {
      const body =
          '{"error":"invalid_grant","error_description":"refresh token expired"}';
      expect(
        OidcManager.summarizeErrorBody(body),
        'invalid_grant: refresh token expired',
      );
    });

    test('hides raw non-JSON HTML error pages', () {
      const html = '<html><body>Internal stack trace secret=123</body></html>';
      expect(OidcManager.summarizeErrorBody(html), 'provider error');
    });

    test('strips control characters and truncates overly long descriptions', () {
      const longLength = 300;
      const maxSummaryLength = 161;
      final longDesc = 'x' * longLength;
      final body =
          '{"error":"invalid_request","error_description":"$longDesc\\nline2"}';
      final summary = OidcManager.summarizeErrorBody(body);

      expect(summary.contains('\n'), isFalse);
      expect(summary.length, lessThanOrEqualTo(maxSummaryLength));
      expect(summary.endsWith('…'), isTrue);
    });
  });
}
