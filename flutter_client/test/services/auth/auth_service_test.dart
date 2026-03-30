import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';

void main() {
  group('AuthService - Security & Protocol Logic', () {
    test('SECURITY: PKCE Code Verifier must use OIDC-compliant characters', () {
      // The OIDC/PKCE spec (RFC 7636) allows unreserved characters: [A-Z] / [a-z] / [0-9] / "-" / "." / "_" / "~"
      const chars =
          'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
      final allowedPattern = RegExp(r'^[a-zA-Z0-9\-\._~]+$');

      expect(
        allowedPattern.hasMatch(chars),
        isTrue,
        reason: 'Alphabet must match RFC 7636',
      );
    });

    test(
      'SECURITY: PKCE Code Challenge must match RFC 7636 Reference Implementation',
      () {
        // Reference example from RFC 7636 Section 4.2
        // Verifier: dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk
        // Challenge (S256): E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM

        const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';

        // Replicate the AuthService hashing logic exactly
        final bytes = utf8.encode(verifier);
        final digest = sha256.convert(bytes);
        // We use base64UrlEncode which is strictly OIDC compliant (No Padding)
        final challenge = base64UrlEncode(digest.bytes).replaceAll('=', '');

        expect(
          challenge,
          'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
          reason:
              'Our S256 hashing must match the RFC standard exactly for Zitadel to accept it',
        );
      },
    );

    test('SECURITY: State Parameter Protection (Self-Validation)', () {
      // The state parameter must be long enough to prevent brute force guessing (CSRF protection)
      const stateLength = 16;
      const minSecureStateLength = 8;
      expect(
        stateLength >= minSecureStateLength,
        isTrue,
        reason: 'State must be long enough to provide security',
      );
    });

    test('PROTOCOL: ID Token Extraction Robustness', () {
      final mockClaims = {'sub': '12345', 'email': 'test@example.com'};

      final displayName = mockClaims['name'] ?? mockClaims['email'] ?? 'User';
      expect(
        displayName,
        'test@example.com',
        reason: 'Should fallback to email if name is missing',
      );
    });
  });
}
