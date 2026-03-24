import 'package:flutter/foundation.dart';
import '../auth/auth_service.dart';
import '../utility/settings_service.dart';
import '../utility/logging_service.dart';

/// Manages observation of Auth and Settings to trigger connectivity changes.
class ConfigurationManager extends ChangeNotifier {
  final AuthService _authService;
  final SettingsService _settingsService;
  final LoggingService _logger = LoggingService();

  String _lastKnownUri;
  String? _lastKnownApiKey;
  bool _lastKnownIncognito;
  String _lastKnownMode;

  // OIDC identity fingerprint — tracks whether the authenticated user or
  // auth state has actually changed.  Prevents unnecessary reconnects on
  // silent token refreshes where the identity is unchanged.
  String? _lastKnownUserId;
  bool _lastKnownIsAuthenticated = false;

  VoidCallback? _onReconnectNeeded;
  VoidCallback? _onAutoConnectDesired;

  ConfigurationManager(this._authService, this._settingsService)
    : _lastKnownUri = _settingsService.serverUri,
      _lastKnownApiKey = _settingsService.cachedApiKey,
      _lastKnownIncognito = _settingsService.incognitoMode,
      _lastKnownMode = _settingsService.transcriptionMode,
      _lastKnownUserId = _authService.currentUser?['id'] as String?,
      _lastKnownIsAuthenticated = _authService.isAuthenticated;

  void startObserving({
    required VoidCallback onReconnectNeeded,
    required VoidCallback onAutoConnectDesired,
  }) {
    _onReconnectNeeded = onReconnectNeeded;
    _onAutoConnectDesired = onAutoConnectDesired;

    // Snapshot auth state at the moment observation starts so an already-
    // authenticated launch doesn't treat the first silent-refresh pulse as
    // a fresh identity change.
    _lastKnownUserId = _authService.currentUser?['id'] as String?;
    _lastKnownIsAuthenticated = _authService.isAuthenticated;

    _authService.addListener(_handleAuthChange);
    _settingsService.addListener(_handleSettingsChange);

    // CRITICAL: Initial state check for launch.
    // In Groq mode the backend is fully dormant — skip auto-connect.
    _logger.info(
      'ConfigurationManager: Starting observation, checking initial state...',
    );
    if (_settingsService.isGroqMode) {
      _logger.info(
        'ConfigurationManager: Groq mode active, backend dormant — skipping auto-connect',
      );
    } else if (_authService.isAuthenticated ||
        (_lastKnownApiKey?.isNotEmpty ?? false)) {
      _logger.info(
        'ConfigurationManager: Valid credentials found on launch, requesting auto-connect',
      );
      _onAutoConnectDesired?.call();
    }
  }

  void stopObserving() {
    _authService.removeListener(_handleAuthChange);
    _settingsService.removeListener(_handleSettingsChange);
  }

  void _handleAuthChange() {
    final currentUserId = _authService.currentUser?['id'] as String?;
    final isAuthenticated = _authService.isAuthenticated;

    // OIDC identity fingerprint: reconnect only when identity state changes.
    // API key, server URI, and incognito are tracked by _handleSettingsChange.
    final bool identityChanged = currentUserId != _lastKnownUserId;
    final bool authStateChanged = isAuthenticated != _lastKnownIsAuthenticated;

    if (identityChanged || authStateChanged) {
      _logger.info(
        'ConfigurationManager: OIDC identity state changed '
        '(identity: $identityChanged, authState: $authStateChanged)',
      );
      _lastKnownUserId = currentUserId;
      _lastKnownIsAuthenticated = isAuthenticated;
      _onReconnectNeeded?.call();
    } else {
      _logger.info(
        'ConfigurationManager: Auth pulse (identity unchanged, skipping reconnect)',
      );
    }

    // Auto-connect if we are authenticated and currently idle.
    // Suppressed in Groq mode — backend is dormant.
    if (isAuthenticated && !_settingsService.isGroqMode) {
      _onAutoConnectDesired?.call();
    }
  }

  void _handleSettingsChange() async {
    final currentUri = _settingsService.serverUri;
    final currentIncognito = _settingsService.incognitoMode;
    final currentApiKey = await _settingsService.getApiKey();
    final currentMode = _settingsService.transcriptionMode;

    // Detect transcription mode change first — it overrides other signals.
    if (currentMode != _lastKnownMode) {
      _logger.info(
        'ConfigurationManager: Transcription mode changed '
        '$_lastKnownMode → $currentMode',
      );
      _lastKnownMode = currentMode;

      if (_settingsService.isGroqMode) {
        // Switching TO Groq: tear down the backend connection immediately.
        _onReconnectNeeded?.call();
        _logger.info(
          'ConfigurationManager: Backend dormant — WebSocket disconnected',
        );
      } else {
        // Switching TO backend: resume normal auto-connect if creds exist.
        if ((currentApiKey?.isNotEmpty ?? false) ||
            _authService.isAuthenticated) {
          _onAutoConnectDesired?.call();
        }
      }
      return;
    }

    // In Groq mode, suppress all backend reconnect/auto-connect signals.
    if (_settingsService.isGroqMode) return;

    bool needsReconnect = false;

    if (currentUri != _lastKnownUri) {
      _logger.info('ConfigurationManager: URI changed');
      _lastKnownUri = currentUri;
      needsReconnect = true;
    }

    if (currentApiKey != _lastKnownApiKey) {
      _logger.info('ConfigurationManager: API Key changed');
      _lastKnownApiKey = currentApiKey;
      needsReconnect = true;
    }

    if (currentIncognito != _lastKnownIncognito) {
      _logger.info('ConfigurationManager: Incognito mode toggled');
      _lastKnownIncognito = currentIncognito;
      needsReconnect = true;
    }

    if (needsReconnect) {
      _onReconnectNeeded?.call();

      // If we have valid credentials now, try to auto-connect
      if ((currentApiKey?.isNotEmpty ?? false) ||
          _authService.isAuthenticated) {
        _onAutoConnectDesired?.call();
      }
    }
  }
}
