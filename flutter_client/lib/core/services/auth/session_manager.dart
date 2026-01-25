import 'package:jwt_decoder/jwt_decoder.dart';
import '../secure_vault_service.dart';

/// Handles session persistence and token metadata extraction.
class SessionManager {
  static const String _vaultIdTokenKey = 'oidc_id_token';
  static const String _vaultAccessTokenKey = 'oidc_access_token';
  static const String _vaultRefreshTokenKey = 'oidc_refresh_token';

  final SecureVaultService _vault = SecureVaultService();

  Future<void> initialize() async {
    await _vault.initialize();
  }

  Future<String?> loadIdToken() async => await _vault.retrieveCredential(_vaultIdTokenKey);
  Future<String?> loadRefreshToken() async => await _vault.retrieveCredential(_vaultRefreshTokenKey);

  Future<void> saveTokens({
    required String idToken,
    String? accessToken,
    String? refreshToken,
  }) async {
    await _vault.storeCredential(_vaultIdTokenKey, idToken);
    if (accessToken != null) {
      await _vault.storeCredential(_vaultAccessTokenKey, accessToken);
    }
    if (refreshToken != null) {
      await _vault.storeCredential(_vaultRefreshTokenKey, refreshToken);
    }
  }

  Future<void> clearSession() async {
    await _vault.deleteCredential(_vaultIdTokenKey);
    await _vault.deleteCredential(_vaultAccessTokenKey);
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
