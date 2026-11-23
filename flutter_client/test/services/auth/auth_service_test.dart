// The managers are mocked fresh for every test; only private mocks live here.
// ignore_for_file: avoid-late-keyword, prefer-match-file-name
import 'package:flutter/services.dart';
import 'package:flutter_client/services/auth/auth_service.dart';
import 'package:flutter_client/services/auth/oidc_manager.dart';
import 'package:flutter_client/services/auth/session_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockOidcManager extends Mock implements OidcManager {}

class _MockSessionManager extends Mock implements SessionManager {}

void main() {
  const nonce = 'generated-nonce';
  const callback = 'whisperdoc://callback';
  late _MockOidcManager oidc;
  late _MockSessionManager session;
  late AuthService auth;

  /// The browser comes back to the app with [query].
  void browserReturns(String query) => when(
    () => oidc.authenticate(
      authorizationEndpoint: any(named: 'authorizationEndpoint'),
      state: any(named: 'state'),
      codeChallenge: any(named: 'codeChallenge'),
    ),
  ).thenAnswer((_) async => '$callback?$query');

  void browserThrows(Object error) => when(
    () => oidc.authenticate(
      authorizationEndpoint: any(named: 'authorizationEndpoint'),
      state: any(named: 'state'),
      codeChallenge: any(named: 'codeChallenge'),
    ),
  ).thenThrow(error);

  void verifyNoTokenRequest() => verifyNever(
    () => oidc.exchangeToken(
      tokenEndpoint: any(named: 'tokenEndpoint'),
      code: any(named: 'code'),
      codeVerifier: any(named: 'codeVerifier'),
    ),
  );

  setUp(() {
    oidc = _MockOidcManager();
    session = _MockSessionManager();
    when(() => oidc.discover()).thenAnswer(
      (_) async => {
        'authorization_endpoint': 'https://idp/authorize',
        'token_endpoint': 'https://idp/token',
      },
    );
    // The verifier and the state are both drawn here.
    when(() => oidc.generateRandomString(any())).thenReturn(nonce);
    when(() => oidc.generateCodeChallenge(nonce)).thenReturn('challenge');
    auth = AuthService(session: session, oidc: oidc);
  });

  group('AuthService.signIn', () {
    test('trades the code, with its verifier, for a session', () async {
      browserReturns('code=auth-code&state=$nonce');
      when(
        () => oidc.exchangeToken(
          tokenEndpoint: any(named: 'tokenEndpoint'),
          code: any(named: 'code'),
          codeVerifier: any(named: 'codeVerifier'),
        ),
      ).thenAnswer((_) async => {'id_token': 'id.token'});
      when(
        () => session.saveTokens(
          idToken: any(named: 'idToken'),
          refreshToken: any(named: 'refreshToken'),
        ),
      ).thenAnswer((_) => Future.value());
      when(() => session.extractUser('id.token')).thenReturn({'id': 'user-1'});

      await auth.signIn();

      expect(auth.idToken, 'id.token');
      verify(
        () => oidc.authenticate(
          authorizationEndpoint: 'https://idp/authorize',
          state: nonce,
          codeChallenge: 'challenge',
        ),
      );
      verify(
        () => oidc.exchangeToken(
          tokenEndpoint: 'https://idp/token',
          code: 'auth-code',
          codeVerifier: nonce,
        ),
      );
    });

    test('rejects a callback carrying another state', () async {
      browserReturns('code=auth-code&state=forged');

      await expectLater(
        auth.signIn(),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('State mismatch'),
          ),
        ),
      );
      expect(auth.isAuthenticated, isFalse);
      verifyNoTokenRequest();
    });

    test('ends quietly when the user closes the browser', () async {
      const attempts = 2;
      browserThrows(
        PlatformException(code: 'CANCELED', message: 'User canceled login'),
      );

      // The second attempt runs too: the first did not stay mid-sign-in.
      for (var i = 0; i < attempts; i++) {
        await auth.signIn();
      }

      expect(auth.isAuthenticated, isFalse);
      verifyNoTokenRequest();
      final discoveries = verify(() => oidc.discover());
      expect(discoveries.callCount, attempts);
    });

    test('passes any other browser failure on to the caller', () async {
      final failure = PlatformException(code: 'EUNKNOWN', message: 'broken');
      browserThrows(failure);

      await expectLater(auth.signIn(), throwsA(same(failure)));
      expect(auth.isAuthenticated, isFalse);
      verifyNoTokenRequest();
    });
  });

  group('AuthService.signIn with an incomplete token response', () {
    test('no id_token stops sign-in and stores nothing', () async {
      browserReturns('code=auth-code&state=$nonce');
      when(
        () => oidc.exchangeToken(
          tokenEndpoint: any(named: 'tokenEndpoint'),
          code: any(named: 'code'),
          codeVerifier: any(named: 'codeVerifier'),
        ),
      ).thenAnswer((_) async => {'access_token': 'only-an-access-token'});

      await expectLater(auth.signIn(), throwsA(isA<FormatException>()));

      expect(auth.isAuthenticated, isFalse);
      verifyNever(
        () => session.saveTokens(
          idToken: any(named: 'idToken'),
          refreshToken: any(named: 'refreshToken'),
        ),
      );
    });
  });
}
