/// Application-wide constants.
///
/// Centralizes magic numbers, default values, and configuration parameters
/// to improve maintainability and reduce scattered hardcoded values.
class AppConstants {
  // === Server Configuration ===
  static const String defaultServerUri = 'ws://localhost:9989/ws';

  // === WebSocket Timeouts ===
  /// Idle timeout before closing the WebSocket connection to save resources.
  static const Duration wsIdleTimeout = Duration(minutes: 3);

  /// Maximum delay between reconnection attempts (exponential backoff cap).
  static const Duration wsMaxReconnectDelay = Duration(seconds: 30);

  // === Hotkey Defaults ===
  static const String defaultHotkeyDisplay = 'Ctrl+Alt+E';

  /// MOD_CONTROL (2) | MOD_ALT (1) = 3
  static const int defaultHotkeyModifiers = 3;

  /// Virtual key code for 'E' (0x45)
  static const int defaultHotkeyVKey = 0x45;

  // === Recording & History ===
  /// Maximum number of transcription entries to keep in history.
  static const int maxHistorySize = 100;

  /// Maximum number of log entries to keep in UI buffer.
  static const int logBufferSize = 500;

  // === UI ===
  /// Default window size for the main application.
  static const double windowWidth = 420;
  static const double windowHeight = 600;

  // === OIDC / Identity Configuration ===
  /// Redirect URI for OAuth callbacks.
  /// Pulls from --dart-define OIDC_REDIRECT_URI
  static const String oidcRedirectUri = String.fromEnvironment(
    'OIDC_REDIRECT_URI',
  );

  /// Zitadel / OIDC Issuer URL
  /// Pulls from --dart-define OIDC_ISSUER
  static const String oidcIssuer = String.fromEnvironment('OIDC_ISSUER');

  /// OIDC Client ID
  /// Pulls from --dart-define OIDC_CLIENT_ID
  static const String oidcClientId = String.fromEnvironment('OIDC_CLIENT_ID');

  /// Discovery URL for OIDC metadata
  static const String oidcDiscoveryUrl =
      '$oidcIssuer/.well-known/openid-configuration';

  /// Scopes required for identity verification
  static const List<String> oidcScopes = [
    'openid',
    'profile',
    'email',
    'offline_access',
  ];
}
