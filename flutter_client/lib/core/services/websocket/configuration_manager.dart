import 'package:flutter/foundation.dart';
import '../auth_service.dart';
import '../settings_service.dart';
import '../logging_service.dart';

/// Manages observation of Auth and Settings to trigger connectivity changes.
class ConfigurationManager extends ChangeNotifier {
  final AuthService _authService;
  final SettingsService _settingsService;
  final LoggingService _logger = LoggingService();

  String _lastKnownUri;
  String? _lastKnownApiKey;
  bool _lastKnownIncognito;

  VoidCallback? _onReconnectNeeded;
  VoidCallback? _onAutoConnectDesired;

  ConfigurationManager(this._authService, this._settingsService)
      : _lastKnownUri = _settingsService.serverUri,
        _lastKnownApiKey = _settingsService.cachedApiKey,
        _lastKnownIncognito = _settingsService.incognitoMode;

  void startObserving({
    required VoidCallback onReconnectNeeded,
    required VoidCallback onAutoConnectDesired,
  }) {
    _onReconnectNeeded = onReconnectNeeded;
    _onAutoConnectDesired = onAutoConnectDesired;

    _authService.addListener(_handleAuthChange);
    _settingsService.addListener(_handleSettingsChange);
  }

  void stopObserving() {
    _authService.removeListener(_handleAuthChange);
    _settingsService.removeListener(_handleSettingsChange);
  }

  void _handleAuthChange() {
    _logger.info('ConfigurationManager: Auth state pulse detected');
    
    // Always trigger a reconnect if we are currently connected to force identity update
    _onReconnectNeeded?.call();

    // If we just became authenticated and are currently idle, trigger auto-connect
    if (_authService.isAuthenticated) {
      _logger.info('ConfigurationManager: System authenticated, requesting auto-connect');
      _onAutoConnectDesired?.call();
    }
  }

  void _handleSettingsChange() async {
    final currentUri = _settingsService.serverUri;
    final currentIncognito = _settingsService.incognitoMode;
    final currentApiKey = await _settingsService.getApiKey();

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
      if ((currentApiKey?.isNotEmpty ?? false) || _authService.isAuthenticated) {
        _onAutoConnectDesired?.call();
      }
    }
  }
}
