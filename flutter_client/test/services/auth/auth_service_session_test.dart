// ignore_for_file: avoid-late-keyword, prefer-match-file-name, no-magic-number, no-empty-block
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_client/services/auth/auth_service.dart';
import 'package:flutter_client/services/auth/oidc_manager.dart';
import 'package:flutter_client/services/auth/session_manager.dart';

class _MockOidcManager extends Mock implements OidcManager {}

class _MockSessionManager extends Mock implements SessionManager {}

void main() {
  const storedToken = 'stored.id.token';
  late _MockOidcManager oidc;
  late _MockSessionManager session;
  late AuthService auth;

  setUp(() {
    oidc = _MockOidcManager();
    session = _MockSessionManager();
    when(() => session.initialize()).thenAnswer((_) async {});
    when(() => session.loadIdToken()).thenAnswer((_) async => storedToken);
    when(() => session.loadRefreshToken()).thenAnswer((_) async => 'refresh');
    when(
      () => session.extractUser(any()),
    ).thenReturn({'sub': 'user-1', 'email': 'user@example.com'});
    when(() => session.clearSession()).thenAnswer((_) async {});
    when(
      () => oidc.discover(),
    ).thenAnswer((_) async => {'token_endpoint': 'https://idp/token'});
    auth = AuthService(oidc: oidc, session: session);
  });

  group('AuthService startup', () {
    test('does not wait on the network to restore an expired session', () async {
      when(() => session.isExpired(storedToken)).thenReturn(true);
      // A refresh that never answers, like a stalled connection.
      final neverAnswers = Completer<Map<String, dynamic>>();
      when(
        () => oidc.exchangeToken(
          tokenEndpoint: any(named: 'tokenEndpoint'),
          refreshToken: any(named: 'refreshToken'),
        ),
      ).thenAnswer((_) => neverAnswers.future);

      await auth.initialize().timeout(const Duration(seconds: 1));

      expect(auth.isAuthenticated, isTrue);
      expect(auth.currentUser?['sub'], equals('user-1'));
    });
  });

  group('AuthService silent refresh policy', () {
    test('keeps the session when the refresh fails transiently', () async {
      when(
        () => oidc.exchangeToken(
          tokenEndpoint: any(named: 'tokenEndpoint'),
          refreshToken: any(named: 'refreshToken'),
        ),
      ).thenThrow(TimeoutException('stalled'));
      when(() => session.isExpired(storedToken)).thenReturn(false);
      await auth.initialize();

      final refreshed = await auth.silentRefresh();

      expect(refreshed, isFalse);
      expect(auth.isAuthenticated, isTrue);
      verifyNever(() => session.clearSession());
    });

    test('signs out when the provider rejects the refresh token', () async {
      when(
        () => oidc.exchangeToken(
          tokenEndpoint: any(named: 'tokenEndpoint'),
          refreshToken: any(named: 'refreshToken'),
        ),
      ).thenThrow(const OidcRejectedException(400, 'invalid_grant'));
      when(() => session.isExpired(storedToken)).thenReturn(false);
      await auth.initialize();

      final refreshed = await auth.silentRefresh();

      expect(refreshed, isFalse);
      expect(auth.isAuthenticated, isFalse);
      final cleared = verify(() => session.clearSession());
      expect(cleared.callCount, equals(1));
    });

    test('concurrent callers share one in-flight refresh', () async {
      final pending = Completer<Map<String, dynamic>>();
      when(
        () => oidc.exchangeToken(
          tokenEndpoint: any(named: 'tokenEndpoint'),
          refreshToken: any(named: 'refreshToken'),
        ),
      ).thenAnswer((_) => pending.future);
      when(
        () => session.saveTokens(
          idToken: any(named: 'idToken'),
          accessToken: any(named: 'accessToken'),
          refreshToken: any(named: 'refreshToken'),
        ),
      ).thenAnswer((_) async {});
      when(() => session.isExpired(storedToken)).thenReturn(false);
      await auth.initialize();

      final first = auth.silentRefresh();
      final second = auth.silentRefresh();
      pending.complete({
        'id_token': 'new.id.token',
        'access_token': 'access',
        'refresh_token': 'refresh-2',
      });

      expect(await Future.wait([first, second]), equals([true, true]));
      final exchanges = verify(
        () => oidc.exchangeToken(
          tokenEndpoint: any(named: 'tokenEndpoint'),
          refreshToken: any(named: 'refreshToken'),
        ),
      );
      expect(exchanges.callCount, equals(1));
      expect(auth.idToken, equals('new.id.token'));
    });
  });
}
