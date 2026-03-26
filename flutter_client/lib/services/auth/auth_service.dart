import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'oidc_manager.dart';
import 'session_manager.dart';

/// Coordinator service for Authentication.
/// Delegates OIDC protocol details and Session persistence to modular managers.
class AuthService extends ChangeNotifier {
  final LoggingService _logger = LoggingService();
  final OidcManager _oidc = OidcManager();
  final SessionManager _session = SessionManager();

  bool _isInitialized = false;
  bool _isAuthenticating = false;
  Map<String, dynamic>? _currentUser;
  String? _idToken;
  Completer<bool>? _refreshCompleter;

  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isAuthenticated => _idToken != null;
  bool get isAuthenticating => _isAuthenticating;
  String? get idToken => _idToken;

  String _formatPrincipal(Map<String, dynamic>? user) {
    final sub = (user?['sub'] ?? 'unknown').toString();
    final email =
        (user?['email'] ?? user?['preferred_username'])?.toString().trim();
    if (email != null && email.isNotEmpty) {
      return 'sub=$sub email=$email';
    }
    return 'sub=$sub';
  }

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }
    await _session.initialize();
    await _loadExistingSession();
    _isInitialized = true;
    _logger.info('AuthService initialized');
  }

  Future<void> _loadExistingSession() async {
    try {
      _idToken = await _session.loadIdToken();

      if (_idToken != null) {
        if (_session.isExpired(_idToken!)) {
          _logger.warning(
            'Stored OIDC session expired. Attempting silent refresh...',
          );
          final success = await silentRefresh();
          if (!success) {
            _logger.warning('Silent refresh failed. User must sign in again.');
            await signOut();
          }
        } else {
          _currentUser = _session.extractUser(_idToken!);
          _logger.info(
            'Restored OIDC session for ${_formatPrincipal(_currentUser)}',
          );
        }
      }
    } catch (e) {
      _logger.error('Failed to load existing session', error: e);
    }
  }

  Future<void> signIn() async {
    if (_isAuthenticating) {
      return;
    }
    _isAuthenticating = true;
    notifyListeners();

    try {
      _logger.info('Initiating OIDC sign-in flow...');

      final discovery = await _oidc.discover();
      final verifier = _oidc.generateRandomString(64);
      final challenge = _oidc.generateCodeChallenge(verifier);
      final state = _oidc.generateRandomString(16);

      final authResult = await _oidc.authenticate(
        authorizationEndpoint: discovery['authorization_endpoint'],
        state: state,
        codeChallenge: challenge,
      );

      final resultUri = Uri.parse(authResult);
      final code = resultUri.queryParameters['code'];
      if (code == null) {
        throw Exception('No code returned');
      }
      if (resultUri.queryParameters['state'] != state) {
        throw Exception('State mismatch');
      }

      final tokens = await _oidc.exchangeToken(
        tokenEndpoint: discovery['token_endpoint'],
        code: code,
        codeVerifier: verifier,
      );

      _idToken = tokens['id_token'];
      await _session.saveTokens(
        idToken: _idToken!,
        accessToken: tokens['access_token'],
        refreshToken: tokens['refresh_token'],
      );

      _currentUser = _session.extractUser(_idToken!);
      _logger.info(
        'Sign-in successful for ${_formatPrincipal(_currentUser)} '
        '(Refresh Token: ${tokens['refresh_token'] != null ? 'YES' : 'NO'})',
      );
    } catch (e) {
      if (!e.toString().contains('CANCELED')) {
        _logger.error('OIDC Sign-in failed', error: e);
      }
    } finally {
      _isAuthenticating = false;
      notifyListeners();
    }
  }

  Future<bool> silentRefresh() async {
    if (_refreshCompleter != null) {
      _logger.info('Silent refresh already in progress, waiting...');
      return _refreshCompleter!.future;
    }
    _refreshCompleter = Completer<bool>();

    try {
      _logger.info('Attempting OIDC silent refresh...');
      final refreshToken = await _session.loadRefreshToken();
      if (refreshToken == null) {
        _logger.warning(
          'Silent refresh aborted: No refresh token found in vault. Signing out user.',
        );
        await signOut();
        _refreshCompleter?.complete(false);
        return false;
      }

      final discovery = await _oidc.discover();
      final tokens = await _oidc.exchangeToken(
        tokenEndpoint: discovery['token_endpoint'],
        refreshToken: refreshToken,
      );

      _idToken = tokens['id_token'];
      await _session.saveTokens(
        idToken: _idToken!,
        accessToken: tokens['access_token'],
        refreshToken: tokens['refresh_token'],
      );

      _currentUser = _session.extractUser(_idToken!);
      _logger.info(
        'Silent refresh successful for ${_formatPrincipal(_currentUser)}',
      );
      notifyListeners();
      _refreshCompleter?.complete(true);
      return true;
    } catch (e) {
      _logger.error('Silent refresh failed. Signing out user.', error: e);
      await signOut();
      _refreshCompleter?.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  Future<void> signOut() async {
    _logger.info('Signing out...');
    await _session.clearSession();
    _idToken = null;
    _currentUser = null;
    notifyListeners();
  }

  Future<String?> getAccessToken() async {
    if (_idToken == null) {
      return null;
    }
    if (_session.isExpired(_idToken!)) {
      final success = await silentRefresh();
      if (!success) return null;
    }
    return _idToken;
  }
}
