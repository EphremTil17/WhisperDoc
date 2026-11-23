import 'dart:convert';

import 'package:flutter_client/services/auth/oidc_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const statusOk = 200;
  const issuer = 'https://idp.example';
  const authorizeUrl = '$issuer/oauth/v2/authorize';
  const tokenUrl = '$issuer/oauth/v2/token';

  /// Every URL the manager asked the network for.
  final requested = <Uri>[];

  setUp(requested.clear);

  /// Runs [body] with the network answering every request with [document].
  Future<T> serving<T>(
    Map<String, String> document,
    Future<T> Function() body,
  ) => http.runWithClient(
    body,
    () => MockClient((request) async {
      requested.add(request.url);

      return http.Response(jsonEncode(document), statusOk);
    }),
  );

  Matcher rejectedFor(String reason) => throwsA(
    isA<Exception>().having((e) => e.toString(), 'message', contains(reason)),
  );

  group('OidcManager PKCE (RFC 7636)', () {
    test('derives the S256 challenge of the Appendix B example', () {
      expect(
        OidcManager().generateCodeChallenge(
          'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
        ),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test(
      'draws fresh verifiers of the asked length from unreserved characters',
      () {
        const verifierLength = 64;
        const draws = 8;
        final oidc = OidcManager();

        final verifiers = {
          for (var i = 0; i < draws; i++)
            oidc.generateRandomString(verifierLength),
        };

        expect(verifiers, hasLength(draws), reason: 'no verifier repeats');
        expect(
          verifiers,
          everyElement(
            allOf(
              hasLength(verifierLength),
              matches(RegExp(r'^[A-Za-z0-9\-._~]+$')),
            ),
          ),
        );
      },
    );
  });

  group('OidcManager issuer trust', () {
    const discovery = {
      'issuer': issuer,
      'authorization_endpoint': authorizeUrl,
      'token_endpoint': tokenUrl,
    };

    test('a build without an issuer refuses before any request', () async {
      final oidc = OidcManager(issuer: '');

      await expectLater(
        serving(discovery, oidc.discover),
        throwsA(isA<StateError>()),
      );
      expect(requested, isEmpty);
    });

    test('discovers from the issuer and keeps its own endpoints', () async {
      final found = await serving(
        discovery,
        OidcManager(issuer: issuer).discover,
      );

      expect(requested, [
        Uri.parse('$issuer/.well-known/openid-configuration'),
      ]);
      expect(found['token_endpoint'], tokenUrl);
    });

    test('rejects a discovery document naming another issuer', () async {
      final forged = {...discovery, 'issuer': 'https://evil.example'};

      await expectLater(
        serving(forged, OidcManager(issuer: issuer).discover),
        rejectedFor('issuer mismatch'),
      );
    });

    for (final (endpoint, reason) in [
      ('https://evil.example/token', 'configured issuer origin'),
      ('https://idp.example:8443/token', 'configured issuer origin'),
      ('http://idp.example/token', 'must use HTTPS'),
      ('/oauth/v2/token', 'absolute URI'),
    ]) {
      test('rejects a discovered endpoint at $endpoint', () async {
        final forged = {...discovery, 'token_endpoint': endpoint};

        await expectLater(
          serving(forged, OidcManager(issuer: issuer).discover),
          rejectedFor(reason),
        );
      });
    }

    test('allows plain HTTP only for a loopback issuer', () async {
      const loopback = 'http://localhost:8080';
      final local = {
        'issuer': loopback,
        'authorization_endpoint': '$loopback/authorize',
        'token_endpoint': '$loopback/token',
      };

      final found = await serving(
        local,
        OidcManager(issuer: loopback).discover,
      );
      expect(found['issuer'], loopback);

      requested.clear();
      await expectLater(
        serving(discovery, OidcManager(issuer: 'http://idp.example').discover),
        rejectedFor('must use HTTPS'),
      );
      expect(requested, isEmpty);
    });

    test('sends no token request to an endpoint off the issuer', () async {
      final oidc = OidcManager(issuer: issuer);

      await expectLater(
        serving(
          discovery,
          () => oidc.exchangeToken(
            tokenEndpoint: 'https://evil.example/token',
            refreshToken: 'refresh',
          ),
        ),
        rejectedFor('configured issuer origin'),
      );
      expect(requested, isEmpty);
    });

    test('opens no browser for an authorization endpoint off the issuer', () {
      final oidc = OidcManager(issuer: issuer);

      expect(
        oidc.authenticate(
          authorizationEndpoint: 'https://evil.example/authorize',
          state: 'state',
          codeChallenge: 'challenge',
        ),
        rejectedFor('configured issuer origin'),
      );
    });
  });

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

  group('OidcManager token response', () {
    test('a token endpoint that answers with no JSON object is refused', () {
      final notAnObject = http.runWithClient(
        () => OidcManager(issuer: issuer).exchangeToken(
          tokenEndpoint: tokenUrl,
          code: 'auth-code',
          codeVerifier: 'verifier',
        ),
        () => MockClient((_) async => http.Response('["id_token"]', statusOk)),
      );

      expect(notAnObject, rejectedFor('invalid document'));
    });
  });
}
