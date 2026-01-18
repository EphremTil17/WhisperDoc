import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_client/core/services/logging_service.dart';
import 'package:flutter_client/core/services/secure_vault_service.dart';
import 'package:flutter_client/core/constants/app_constants.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

class AuthService extends ChangeNotifier {
  final LoggingService _logger = LoggingService();

  // Credentials stored in Vault
  static const String _vaultIdTokenKey = 'oidc_id_token';
  static const String _vaultAccessTokenKey = 'oidc_access_token';
  static const String _vaultRefreshTokenKey = 'oidc_refresh_token';

  bool _isInitialized = false;
  bool _isAuthenticating = false;
  Map<String, dynamic>? _currentUser;
  String? _idToken;

  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isAuthenticated => _idToken != null;
  bool get isAuthenticating => _isAuthenticating;
  String? get idToken => _idToken;

  Future<void> initialize() async {
    if (_isInitialized) return;
    await _loadExistingSession();
    _isInitialized = true;
    _logger.info('AuthService initialized');
  }

  Future<void> _loadExistingSession() async {
    try {
      final vault = SecureVaultService();
      await vault.initialize();
      _idToken = await vault.retrieveCredential(_vaultIdTokenKey);

      if (_idToken != null) {
        if (JwtDecoder.isExpired(_idToken!)) {
          _logger.warning('Stored OIDC session expired. Clearing.');
          await signOut();
        } else {
          _updateUserData(_idToken!);
          _logger.info('Restored OIDC session for: ${_currentUser?['email']}');
        }
      }
    } catch (e) {
      _logger.error('Failed to load existing session', error: e);
    }
  }

  Future<void> signIn() async {
    if (_isAuthenticating) {
      _logger.warning('Authentication already in progress. Ignoring request.');
      return;
    }

    _isAuthenticating = true;
    notifyListeners();

    try {
      _logger.info('Initiating OIDC sign-in flow (PKCE)...');

      // 1. Discovery
      final discoveryResponse = await http.get(
        Uri.parse(AppConstants.oidcDiscoveryUrl),
      );
      if (discoveryResponse.statusCode != 200) {
        throw Exception(
          'Failed to discover OIDC endpoints: ${discoveryResponse.body}',
        );
      }
      final discovery = jsonDecode(discoveryResponse.body);
      final authorizationEndpoint = discovery['authorization_endpoint'];
      final tokenEndpoint = discovery['token_endpoint'];

      // 2. Prepare PKCE
      final String codeVerifier = _generateRandomString(64);
      final String codeChallenge = _generateCodeChallenge(codeVerifier);
      final String state = _generateRandomString(16);

      // 3. Construct Authorization URL
      final authUri = Uri.parse(authorizationEndpoint).replace(
        queryParameters: {
          'client_id': AppConstants.oidcClientId,
          'redirect_uri': AppConstants.oidcRedirectUri,
          'response_type': 'code',
          'scope': AppConstants.oidcScopes.join(' '),
          'state': state,
          'code_challenge': codeChallenge,
          'code_challenge_method': 'S256',
        },
      );

      _logger.info('Opening system browser for auth...');

      // 4. Authenticate via Default System Browser
      final authResult = await FlutterWebAuth2.authenticate(
        url: authUri.toString(),
        callbackUrlScheme:
            AppConstants.oidcRedirectUri, // Now http://localhost:4242
        options: const FlutterWebAuth2Options(
          useWebview: false, // Force default browser
        ),
      );

      final resultUri = Uri.parse(authResult);
      final code = resultUri.queryParameters['code'];
      final returnedState = resultUri.queryParameters['state'];

      if (code == null) {
        throw Exception('No code returned from authorization server');
      }
      if (returnedState != state) {
        throw Exception('State mismatch! Potential CSRF attack.');
      }

      _logger.info('Auth code received. Exchanging for tokens...');

      // 5. Exchange Code for Tokens
      final tokenResponse = await http.post(
        Uri.parse(tokenEndpoint),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'authorization_code',
          'client_id': AppConstants.oidcClientId,
          'redirect_uri': AppConstants.oidcRedirectUri,
          'code': code,
          'code_verifier': codeVerifier,
        },
      );

      if (tokenResponse.statusCode != 200) {
        throw Exception('Token exchange failed: ${tokenResponse.body}');
      }

      final tokens = jsonDecode(tokenResponse.body);
      _idToken = tokens['id_token'];
      final accessToken = tokens['access_token'];
      final refreshToken = tokens['refresh_token'];

      if (_idToken == null) {
        throw Exception('No ID Token returned from server');
      }

      // 6. Persist and Update UI
      final vault = SecureVaultService();
      await vault.initialize();
      await vault.storeCredential(_vaultIdTokenKey, _idToken!);
      if (accessToken != null) {
        await vault.storeCredential(_vaultAccessTokenKey, accessToken);
      }
      if (refreshToken != null) {
        await vault.storeCredential(_vaultRefreshTokenKey, refreshToken);
      }

      _updateUserData(_idToken!);
      _logger.info('Sign-in successful: ${_currentUser?['email']}');
    } catch (e) {
      if (e.toString().contains('CANCELED')) {
        _logger.warning('OIDC Sign-in was canceled by the user.');
        return;
      }
      _logger.error('OIDC Sign-in failed', error: e);
      rethrow;
    } finally {
      _isAuthenticating = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    try {
      _logger.info('Signing out...');
      final vault = SecureVaultService();
      await vault.initialize();
      await vault.deleteCredential(_vaultIdTokenKey);
      await vault.deleteCredential(_vaultAccessTokenKey);
      await vault.deleteCredential(_vaultRefreshTokenKey);
      _idToken = null;
      _currentUser = null;
      notifyListeners();
    } catch (e) {
      _logger.error('Logout failed', error: e);
    }
  }

  /// Extracts user metadata from the ID Token
  void _updateUserData(String token) {
    try {
      final Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
      _currentUser = {
        'id': decodedToken['sub'],
        'email': decodedToken['email'],
        'name': decodedToken['name'] ?? decodedToken['preferred_username'],
        'picture': decodedToken['picture'],
      };
    } catch (e) {
      _logger.error('Failed to decode user data', error: e);
    }
  }

  /// Returns the current valid ID Token for backend authentication.
  /// Used by WebSocketService to cage audio transmission.
  Future<String?> getAccessToken() async {
    if (_idToken == null) {
      return null;
    }
    if (JwtDecoder.isExpired(_idToken!)) {
      return null;
    }
    return _idToken;
  }

  // --- OIDC Helpers ---

  String _generateRandomString(int length) {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';
    final random = Random.secure();
    return List.generate(
      length,
      (index) => chars[random.nextInt(chars.length)],
    ).join();
  }

  String _generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}
