import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'oidc_manager.dart';
import 'session_manager.dart';

/// Coordinator service for Authentication.
/// Delegates OIDC protocol details and Session persistence to modular managers.
class AuthService extends ChangeNotifier {
  static const _pkceVerifierLength = 64;
  static const _stateLength = 16;

  final LoggingService _logger = LoggingService();
  final OidcManager _oidc;
  final SessionManager _session;

  AuthService({required SessionManager session, OidcManager? oidc})
    : _session = session,
      _oidc = oidc ?? OidcManager();

  bool _isInitialized = false;
  bool _isAuthenticating = false;
  Map<String, dynamic>? _currentUser;
  String? _idToken;
  Completer<bool>? _refreshCompleter;

  Map<String, dynamic>? get currentUser => _currentUser;
  bool get isAuthenticated => _idToken != null;
  bool get isAuthenticating => _isAuthenticating;
  String? get idToken => _idToken;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }
    await _session.initialize();
    await _loadExistingSession();
    _isInitialized = true;
    _logger.info('AuthService initialized');
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
      final verifier = _oidc.generateRandomString(_pkceVerifierLength);
      final challenge = _oidc.generateCodeChallenge(verifier);
      final state = _oidc.generateRandomString(_stateLength);

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

      final signInIdToken = tokens['id_token'] as String;
      _idToken = signInIdToken;
      await _session.saveTokens(
        idToken: signInIdToken,
        accessToken: tokens['access_token'],
        refreshToken: tokens['refresh_token'],
      );

      _currentUser = _session.extractUser(signInIdToken);
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

  /// Refreshes the session; concurrent callers share one in-flight request.
  ///
  /// Signs out only when the session is definitively unusable (no refresh
  /// token, or the provider rejects it). Network failures and timeouts keep
  /// the session so the next connection attempt retries instead of forcing
  /// the user through a full sign-in.
  Future<bool> silentRefresh() async {
    final inFlight = _refreshCompleter;
    if (inFlight != null) {
      _logger.info('Silent refresh already in progress, waiting...');

      return inFlight.future;
    }
    final completer = _refreshCompleter = Completer<bool>();
    final success = await _refreshTokens();
    _refreshCompleter = null;
    completer.complete(success);

    return success;
  }

  Future<bool> _refreshTokens() async {
    try {
      _logger.info('Attempting OIDC silent refresh...');
      final refreshToken = await _session.loadRefreshToken();
      if (refreshToken == null) {
        _logger.warning(
          'Silent refresh aborted: No refresh token found in vault. Signing out user.',
        );
        await signOut();

        return false;
      }

      final discovery = await _oidc.discover();
      final tokens = await _oidc.exchangeToken(
        tokenEndpoint: discovery['token_endpoint'],
        refreshToken: refreshToken,
      );

      final refreshedIdToken = tokens['id_token'] as String;
      _idToken = refreshedIdToken;
      await _session.saveTokens(
        idToken: refreshedIdToken,
        accessToken: tokens['access_token'],
        refreshToken: tokens['refresh_token'],
      );

      _currentUser = _session.extractUser(refreshedIdToken);
      _logger.info(
        'Silent refresh successful for ${_formatPrincipal(_currentUser)}',
      );
      notifyListeners();

      return true;
    } on OidcRejectedException catch (e) {
      _logger.warning('Refresh token rejected by identity provider: $e');
      await signOut();

      return false;
    } catch (e) {
      _logger.warning('Silent refresh failed transiently; keeping session: $e');

      return false;
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
    final token = _idToken;
    if (token == null) {
      return null;
    }
    if (_session.isExpired(token)) {
      final success = await silentRefresh();
      if (!success) return null;
    }

    return _idToken;
  }

  String _formatPrincipal(Map<String, dynamic>? user) {
    final sub = (user?['sub'] ?? 'unknown').toString();
    final email = (user?['email'] ?? user?['preferred_username'])
        ?.toString()
        .trim();
    if (email != null && email.isNotEmpty) {
      return 'sub=$sub email=$email';
    }

    return 'sub=$sub';
  }

  /// Restores the stored session without network IO so startup never waits on
  /// the identity provider. An expired token refreshes in the background;
  /// [getAccessToken] joins that in-flight refresh when a connection needs it.
  Future<void> _loadExistingSession() async {
    try {
      final storedToken = await _session.loadIdToken();
      if (storedToken == null) return;

      _idToken = storedToken;
      _currentUser = _session.extractUser(storedToken);
      if (_session.isExpired(storedToken)) {
        _logger.info('Stored OIDC session expired; refreshing in background.');
        unawaited(silentRefresh());
      } else {
        _logger.info(
          'Restored OIDC session for ${_formatPrincipal(_currentUser)}',
        );
      }
    } catch (e) {
      _logger.error('Failed to load existing session', error: e);
    }
  }
}
