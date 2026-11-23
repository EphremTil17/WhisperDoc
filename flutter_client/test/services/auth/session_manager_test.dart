import 'dart:convert';

import 'package:flutter_client/services/auth/session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/in_memory_vault.dart';

void main() {
  const idTokenKey = 'oidc_id_token';
  const refreshTokenKey = 'oidc_refresh_token';
  const legacyAccessTokenKey = 'oidc_access_token';

  /// An unsigned JWT carrying [claims]; SessionManager only reads claims.
  String jwt(Map<String, Object?> claims) {
    String part(Map<String, Object?> json) =>
        base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

    return '${part({'alg': 'none', 'typ': 'JWT'})}.${part(claims)}.signature';
  }

  int epochSeconds(DateTime time) =>
      time.millisecondsSinceEpoch ~/ Duration.millisecondsPerSecond;

  group('SessionManager tokens', () {
    test('initialize prepares the shared vault', () async {
      final vault = InMemoryVault();

      await SessionManager(vault: vault).initialize();

      expect(vault.initializeCalls, 1);
    });

    test('saved tokens load back from the vault', () async {
      final vault = InMemoryVault();
      await SessionManager(vault: vault)
          .saveTokens(idToken: 'id-1', refreshToken: 'refresh-1');

      final reloaded = SessionManager(vault: vault);

      expect(await reloaded.loadIdToken(), 'id-1');
      expect(await reloaded.loadRefreshToken(), 'refresh-1');
      expect(
        vault.entries.keys,
        unorderedEquals([idTokenKey, refreshTokenKey]),
      );
    });

    test('a refresh without a new refresh token keeps the old one', () async {
      final vault = InMemoryVault();
      final session = SessionManager(vault: vault);
      await session.saveTokens(idToken: 'id-1', refreshToken: 'refresh-1');

      await session.saveTokens(idToken: 'id-2');

      expect(await session.loadIdToken(), 'id-2');
      expect(await session.loadRefreshToken(), 'refresh-1');
    });

    test('nothing stored loads as null', () async {
      final session = SessionManager(vault: InMemoryVault());

      expect(await session.loadIdToken(), isNull);
      expect(await session.loadRefreshToken(), isNull);
    });

    test('clearSession removes every token, including pre-3.1 ones', () async {
      final vault = InMemoryVault();
      vault.entries[legacyAccessTokenKey] = 'old-access-token';
      vault.entries['api_key'] = 'unrelated';
      final session = SessionManager(vault: vault);
      await session.saveTokens(idToken: 'id-1', refreshToken: 'refresh-1');

      await session.clearSession();

      expect(await session.loadIdToken(), isNull);
      expect(await session.loadRefreshToken(), isNull);
      expect(vault.entries, {'api_key': 'unrelated'});
    });
  });

  group('SessionManager claims', () {
    final session = SessionManager(vault: InMemoryVault());

    test('extractUser reads the profile claims of an ID token', () {
      final token = jwt({
        'sub': 'user-42',
        'email': 'ada@example.com',
        'name': 'Ada Lovelace',
        'preferred_username': 'ada',
        'picture': 'https://example.com/ada.png',
      });

      expect(session.extractUser(token), {
        'id': 'user-42',
        'email': 'ada@example.com',
        'name': 'Ada Lovelace',
        'picture': 'https://example.com/ada.png',
      });
    });

    test('extractUser falls back to the username without a name', () {
      final token = jwt({'sub': 'user-7', 'preferred_username': 'grace'});

      final user = session.extractUser(token);

      expect(user?['name'], 'grace');
      expect(user?['email'], isNull);
    });

    test('extractUser rejects a token that is not a JWT', () {
      expect(session.extractUser('not-a-jwt'), isNull);
      expect(session.extractUser('a.%%%.c'), isNull);
    });

    test('isExpired follows the exp claim', () {
      final now = DateTime.now();
      final expired = jwt({
        'exp': epochSeconds(now.subtract(const Duration(hours: 1))),
      });
      final valid = jwt({
        'exp': epochSeconds(now.add(const Duration(hours: 1))),
      });

      expect(session.isExpired(expired), isTrue);
      expect(session.isExpired(valid), isFalse);
    });
  });
}
