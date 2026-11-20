import 'package:jwt_decoder/jwt_decoder.dart';
import '../utility/secure_vault_service.dart';

/// Handles session persistence and token metadata extraction.
class SessionManager {
  static const String _vaultIdTokenKey = 'oidc_id_token';
  static const String _vaultLegacyAccessTokenKey = 'oidc_access_token';
  static const String _vaultRefreshTokenKey = 'oidc_refresh_token';

  /// The app-wide vault. Shared rather than owned: each vault instance runs a
  /// full PBKDF2 key derivation on initialize.
  final SecureVaultService _vault;

  SessionManager({required SecureVaultService vault}) : _vault = vault;

  Future<void> initialize() async {
    await _vault.initialize();
  }

  Future<String?> loadIdToken() async =>
      await _vault.retrieveCredential(_vaultIdTokenKey);
  Future<String?> loadRefreshToken() async =>
      await _vault.retrieveCredential(_vaultRefreshTokenKey);

  /// Persists the tokens the app actually uses: the ID token (sent in the
  /// backend handshake) and the refresh token. The OAuth access token is
  /// never read, so it is not stored.
  Future<void> saveTokens({
    required String idToken,
    String? refreshToken,
  }) async {
    await _vault.storeCredential(_vaultIdTokenKey, idToken);
    if (refreshToken != null) {
      await _vault.storeCredential(_vaultRefreshTokenKey, refreshToken);
    }
  }

  Future<void> clearSession() async {
    await _vault.deleteCredential(_vaultIdTokenKey);
    // Purges access tokens persisted by versions before 3.1.
    await _vault.deleteCredential(_vaultLegacyAccessTokenKey);
    await _vault.deleteCredential(_vaultRefreshTokenKey);
  }

  Map<String, dynamic>? extractUser(String idToken) {
    try {
      final decoded = JwtDecoder.decode(idToken);

      return {
        'id': decoded['sub'],
        'email': decoded['email'],
        'name': decoded['name'] ?? decoded['preferred_username'],
        'picture': decoded['picture'],
      };
    } catch (_) {
      return null;
    }
  }

  bool isExpired(String token) => JwtDecoder.isExpired(token);
}
