/// Application-wide constants.
///
/// Centralizes magic numbers, default values, and configuration parameters
/// to improve maintainability and reduce scattered hardcoded values.
class AppConstants {
  // === Build Configuration ===

  /// The GitHub repository path.
  static const String githubRepo = 'EphremTil17/WhisperDoc';

  /// URL for the latest releases page (User Fallback).
  static const String updateUrl =
      'https://github.com/$githubRepo/releases/latest';

  /// GitHub API endpoint for the latest release metadata.
  static const String githubApiLatestRelease =
      'https://api.github.com/repos/$githubRepo/releases/latest';

  // === Server Configuration ===
  static const String defaultServerUri = 'https://whisper.ephremst.com';

  // === WebSocket Timeouts ===
  /// Idle timeout before closing the WebSocket connection to save resources.
  static const Duration wsIdleTimeout = Duration(minutes: 5);

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

  // === Groq Cloud Configuration ===

  /// Groq transcription API endpoint (OpenAI-compatible).
  static const String groqTranscriptionEndpoint =
      'https://api.groq.com/openai/v1/audio/transcriptions';

  /// Supported Groq ASR models.
  static const String groqModelLargeV3Turbo = 'whisper-large-v3-turbo';
  static const String groqModelLargeV3 = 'whisper-large-v3';

  static const List<String> groqSupportedModels = [
    groqModelLargeV3Turbo,
    groqModelLargeV3,
  ];

  static const Map<String, String> groqModelDisplayNames = {
    groqModelLargeV3Turbo: 'Large v3 Turbo',
    groqModelLargeV3: 'Large v3',
  };

  /// Default Groq ASR model.
  static const String groqDefaultModel = groqModelLargeV3Turbo;

  /// Conservative buffer ceiling: 24 MB raw PCM, leaving ~1 MB headroom for
  /// the 44-byte WAV header and multipart framing overhead against the 25 MB
  /// free-tier API limit.
  static const int groqMaxBufferBytes = 24 * 1024 * 1024;

  /// At 16 kHz / 16-bit / mono (32 000 bytes/s), 24 MB ≈ 12 min 30 s.
  static const Duration groqMaxRecordingDuration = Duration(
    minutes: 12,
    seconds: 30,
  );

  /// Free-tier rate limits (organisation-level).
  static const int groqMaxRpm = 20;
  static const int groqMaxRpd = 2000;

  /// HTTP timeout for the Groq REST call.
  static const Duration groqHttpTimeout = Duration(seconds: 30);

  /// ISO-639-1 language codes accepted by Groq's Whisper API.
  /// Source: Groq API error response (2026-03-24).
  static const Set<String> groqSupportedLanguages = {
    'af',
    'am',
    'ar',
    'as',
    'az',
    'ba',
    'be',
    'bg',
    'bn',
    'bo',
    'br',
    'bs',
    'ca',
    'cs',
    'cy',
    'da',
    'de',
    'el',
    'en',
    'es',
    'et',
    'eu',
    'fa',
    'fi',
    'fo',
    'fr',
    'gl',
    'gu',
    'ha',
    'haw',
    'he',
    'hi',
    'hr',
    'ht',
    'hu',
    'hy',
    'id',
    'is',
    'it',
    'ja',
    'jv',
    'ka',
    'kk',
    'km',
    'kn',
    'ko',
    'la',
    'lb',
    'ln',
    'lo',
    'lt',
    'lv',
    'mg',
    'mi',
    'mk',
    'ml',
    'mn',
    'mr',
    'ms',
    'mt',
    'my',
    'ne',
    'nl',
    'nn',
    'no',
    'oc',
    'pa',
    'pl',
    'ps',
    'pt',
    'ro',
    'ru',
    'sa',
    'sd',
    'si',
    'sk',
    'sl',
    'sn',
    'so',
    'sq',
    'sr',
    'su',
    'sv',
    'sw',
    'ta',
    'te',
    'tg',
    'th',
    'tk',
    'tl',
    'tr',
    'tt',
    'uk',
    'ur',
    'uz',
    'vi',
    'yi',
    'yo',
    'yue',
    'zh',
  };

  /// Validates a language code against the Groq supported set.
  /// Empty string is valid (means auto-detect).
  static bool isValidGroqLanguage(String code) =>
      code.isEmpty ||
      groqSupportedLanguages.contains(code.trim().toLowerCase());

  /// Checks whether [model] is a supported Groq ASR model.
  static bool isValidGroqModel(String model) =>
      groqSupportedModels.contains(model.trim());

  // === Groq LLM Transform Configuration ===

  /// Groq chat completions endpoint (OpenAI-compatible).
  static const String groqChatCompletionsEndpoint =
      'https://api.groq.com/openai/v1/chat/completions';

  /// Default rewrite model. Verified active via scripts/benchmark_llm_providers.py (2026-09-05).
  /// Measured latency: TTFT ~217ms, Generation ~45ms, Total ~261ms on 27B parameters.
  static const String groqTransformModel = 'qwen/qwen3.8-27b';

  static const double groqTransformTemperature = 0.1;

  /// Timeout scales with input so long dictations are not silently dropped
  /// to raw. total = base + perWord * wordCount, clamped to [base, max].
  static const Duration groqTransformTimeoutBase = Duration(milliseconds: 1500);
  static const Duration groqTransformTimeoutPerWord = Duration(
    milliseconds: 25,
  );
  static const Duration groqTransformTimeoutMax = Duration(seconds: 8);

  /// Output token ceiling scales with input: clamp(2 * estimatedInputTokens, min, max).
  /// Rough estimate: 1 token per 3 characters.
  static const int groqTransformMinCompletionTokens = 128;
  static const int groqTransformMaxCompletionTokens = 4096;
  static const int groqTransformCharsPerToken = 3;

  /// Output length sanity bounds relative to input character count.
  /// Results outside this band are treated as hallucination/truncation and rejected.
  /// Set to 4.5 to accommodate structured technical specifications with markdown and backticks.
  static const double groqTransformMinLengthRatio = 0.3;
  static const double groqTransformMaxLengthRatio = 4.5;

  // === Custom Dictation Profiles ===

  /// Maximum character length of the user-authored portion of a custom
  /// system prompt. The shared preamble is prepended and is not counted.
  static const int customProfileMaxPromptLength = 2000;

  /// Maximum character length for custom profile display names.
  static const int customProfileMaxNameLength = 24;
}
