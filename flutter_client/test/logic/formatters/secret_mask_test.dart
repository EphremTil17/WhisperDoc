import 'package:flutter_client/logic/formatters/secret_mask.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SecretMask.of', () {
    test('shows the first and last four characters of a long key', () {
      expect(SecretMask.of('gsk_abcdefghijklmnop3f2a'), 'gsk_…3f2a');
    });

    test('hides a short secret entirely', () {
      expect(SecretMask.of('short'), '••••');
    });

    test('is empty when there is no secret', () {
      expect(SecretMask.of(null), '');
      expect(SecretMask.of(''), '');
    });
  });
}
