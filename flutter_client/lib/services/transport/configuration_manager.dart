import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_client/logic/models/transcription_source.dart';

import '../auth/auth_service.dart';
import '../utility/settings_service.dart';
import '../utility/logging_service.dart';

/// Manages observation of Auth and Settings to trigger connectivity changes.
class ConfigurationManager {
  final AuthService _authService;
  final SettingsService _settingsService;
  final LoggingService _logger = LoggingService();

  String _lastKnownUri;
  String? _lastKnownApiKey;
  bool _lastKnownIncognito;
  TranscriptionSource _lastKnownSource;

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
      _lastKnownSource = _settingsService.transcriptionSource,
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
    // With a cloud source the backend is fully dormant — skip auto-connect.
    _logger.info(
      'ConfigurationManager: Starting observation, checking initial state...',
    );
    if (_settingsService.transcriptionSource.isCloud) {
      _logger.info(
        'ConfigurationManager: cloud source active, backend dormant — skipping auto-connect',
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
      // Trust was given by the account that just left (signed out, or
      // another account signed in): the next one decides for itself.
      final signedOut = _lastKnownIsAuthenticated && !isAuthenticated;
      final switchedAccount = _lastKnownUserId != null && identityChanged;
      if (signedOut || switchedAccount) {
        unawaited(_settingsService.clearTrustedServers());
      }
      _lastKnownUserId = currentUserId;
      _lastKnownIsAuthenticated = isAuthenticated;
      _onReconnectNeeded?.call();
    } else {
      _logger.info(
        'ConfigurationManager: Auth pulse (identity unchanged, skipping reconnect)',
      );
    }

    // Auto-connect if we are authenticated and currently idle.
    // Suppressed for a cloud source — backend is dormant.
    if (isAuthenticated && !_settingsService.transcriptionSource.isCloud) {
      _onAutoConnectDesired?.call();
    }
  }

  void _handleSettingsChange() {
    final currentUri = _settingsService.serverUri;
    final currentIncognito = _settingsService.incognitoMode;
    final currentApiKey = _settingsService.cachedApiKey;
    final currentSource = _settingsService.transcriptionSource;
    final wasCloud = _lastKnownSource.isCloud;
    final sourceChanged = currentSource != _lastKnownSource;
    final connectionChanged =
        currentUri != _lastKnownUri ||
        currentApiKey != _lastKnownApiKey ||
        currentIncognito != _lastKnownIncognito;

    // Record every value on every change, cloud sources included, so a later
    // unrelated change can't be mistaken for one made while dormant.
    _lastKnownSource = currentSource;
    _lastKnownUri = currentUri;
    _lastKnownApiKey = currentApiKey;
    _lastKnownIncognito = currentIncognito;

    if (currentSource.isCloud) {
      // Leaving the server tears its connection down, with no reconnect.
      // Moving between cloud sources leaves it dormant.
      if (sourceChanged && !wasCloud) {
        _logger.info(
          'ConfigurationManager: ${currentSource.label} on, backend dormant',
        );
        _onReconnectNeeded?.call();
      }

      return;
    }

    if (sourceChanged) {
      _logger.info('ConfigurationManager: Server mode on');
    } else if (connectionChanged) {
      _logger.info('ConfigurationManager: Server, key or incognito changed');
      _onReconnectNeeded?.call();
    } else {
      return;
    }

    if ((currentApiKey?.isNotEmpty ?? false) || _authService.isAuthenticated) {
      _onAutoConnectDesired?.call();
    }
  }
}
