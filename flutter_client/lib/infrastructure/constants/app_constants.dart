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

  /// Upper bound for opening the socket. Without it a black-holed tunnel
  /// holds `_isConnecting` for the full OS TCP timeout, blocking retries and
  /// the recording path's `ensureConnected()`.
  static const Duration wsConnectTimeout = Duration(seconds: 10);

  /// How long after a dictation ends the server's transcript is accepted.
  /// Long clips on a CPU-only server can take a while; outside this window a
  /// transcript is ignored, so a server can't paste text unasked.
  static const Duration serverTranscriptTimeout = Duration(minutes: 2);

  // === Hotkey Defaults ===
  static const String defaultHotkeyDisplay = 'Ctrl+Alt+E';

  /// MOD_CONTROL (2) | MOD_ALT (1) = 3
  static const int defaultHotkeyModifiers = 3;

  /// Virtual key code for 'E' (0x45)
  static const int defaultHotkeyVKey = 0x45;

  // === Recording & History ===
  /// Transcription entries kept (and shown); older rows are pruned on save.
  static const int maxHistorySize = 100;

  /// Quiet period after the last OS audio-endpoint notification before
  /// re-enumerating devices. Measured bursts last ~40 ms, and Windows' device
  /// list lags the first notification, so re-checking immediately reads stale
  /// state; this leaves ~6x headroom over the burst.
  static const Duration audioDeviceChangeSettle = Duration(milliseconds: 250);

  // === UI ===
  /// Client-area size the layout is designed for. The window frame is grown
  /// around it at startup (see main.dart).
  static const double windowWidth = 420;
  static const double windowHeight = 600;

  /// Bundled fonts (text and icons) and their licence files, registered with
  /// LicenseRegistry.
  static const List<(String, String)> bundledFontLicenses = [
    ('Lexend', 'assets/fonts/Lexend-OFL.txt'),
    ('JetBrains Mono', 'assets/fonts/JetBrainsMono-OFL.txt'),
    ('Lucide', 'assets/fonts/Lucide-LICENSE.txt'),
  ];

  // === OIDC / Identity Configuration ===
  /// Upper bound for each OIDC HTTP call (discovery, token exchange). Without
  /// it a stalled connection can hang a token refresh indefinitely.
  static const Duration oidcHttpTimeout = Duration(seconds: 10);

  /// Redirect URI for OAuth callbacks.
  /// Pulls from --dart-define OIDC_REDIRECT_URI
  static const String oidcRedirectUri = String.fromEnvironment(
    'OIDC_REDIRECT_URI',
  );

  /// Issuer URL of the OIDC provider (any; the reference setup is Authentik)
  /// Pulls from --dart-define OIDC_ISSUER
  static const String oidcIssuer = String.fromEnvironment('OIDC_ISSUER');

  /// OIDC Client ID
  /// Pulls from --dart-define OIDC_CLIENT_ID
  static const String oidcClientId = String.fromEnvironment('OIDC_CLIENT_ID');

  /// Scopes required for identity verification
  static const List<String> oidcScopes = [
    'openid',
    'profile',
    'email',
    'offline_access',
  ];

  // === Cloud services (Groq, OpenRouter) ===

  /// Raw PCM per second of audio: 16 kHz, 16-bit, mono.
  static const int pcmBytesPerSecond = 32000;

  /// How long the shared connection may sit idle and still be reused. A
  /// dictation starts it warm and uploads when it stops, so this outlasts a
  /// long recording; the services' own keep-alive limits are minutes longer.
  static const Duration cloudIdleTimeout = Duration(seconds: 120);

  /// The warm-up request opens the connection; it never needs long.
  static const Duration cloudWarmUpTimeout = Duration(seconds: 5);

  // === OpenRouter ===

  static const String openRouterOrigin = 'https://openrouter.ai';
  static const String openRouterApiBase = '$openRouterOrigin/api/v1';

  /// Every speech model OpenRouter serves takes JSON with base64 audio;
  /// some refuse multipart, and JSON measured no slower.
  static const String openRouterTranscriptionEndpoint =
      '$openRouterApiBase/audio/transcriptions';
  static const String openRouterChatEndpoint =
      '$openRouterApiBase/chat/completions';
  static const String openRouterModelsEndpoint = '$openRouterApiBase/models';

  /// Where to compare the models before choosing: OpenRouter's own table
  /// (latency, price, hosts) and Artificial Analysis's accuracy benchmark.
  /// Linked, not fetched, so the app keeps no ranking to maintain.
  static const String openRouterCompareUrl =
      '$openRouterOrigin/models?fmt=table&output_modalities=transcription';
  static const String speechAccuracyUrl =
      'https://artificialanalysis.ai/speech-to-text';

  /// Chosen on first use: the most accurate model with a zero-retention host
  /// when this shipped (2.0% word error, Artificial Analysis, 2026-11-23).
  /// If OpenRouter stops serving it, the first listed model is used.
  static const String openRouterDefaultModel = 'microsoft/mai-transcribe-2';

  /// Base64 grows audio by a third and OpenRouter takes requests up to 25 MB
  /// (decimal): 17 MiB of PCM is 23.8 MB encoded, leaving room for the JSON
  /// around it. About 9 min 17 s of audio.
  static const int openRouterMaxBufferBytes = 17 * 1024 * 1024;

  /// OpenRouter's hosts stop processing after 60 s; the rest is upload.
  static const Duration openRouterHttpTimeout = Duration(seconds: 75);

  /// The model list is fetched again when older than this.
  static const Duration openRouterCatalogMaxAge = Duration(hours: 12);

  /// Latency is OpenRouter's last 30 minutes of traffic, so the picker
  /// reads it again after this.
  static const Duration openRouterLatencyMaxAge = Duration(minutes: 10);

  /// Models whose latency is fetched at once (one small request each).
  static const int openRouterLatencyBatch = 6;

  static const Duration openRouterCatalogTimeout = Duration(seconds: 15);

  /// The default rewrite model on OpenRouter: the one the styles are tuned
  /// for on Groq, with zero data retention. Of 13 models measured, smaller
  /// ones saved at most ~0.13 s and lost the code formatting (2026-11-23).
  /// See docs/benchmarks/rewrite_models.md.
  static const String openRouterTransformModel = 'qwen/qwen3.8-27b';

  /// How the default rewrite model is named where it is offered.
  static const String openRouterTransformModelName = 'Qwen3.8 27B';

  /// Hosts writing at least this many tokens a second (median) are tried
  /// first, quickest to answer among them. A rewrite is ~75 tokens, so this
  /// beat sorting by latency alone: median 0.45 s against 0.71 s for Qwen,
  /// 0.44 s against 0.63 s for DeepSeek V4.1 Flash; 150 helped far less
  /// (2026-11-23).
  static const int openRouterRewriteMinThroughput = 200;

  /// Room for the one-word answer that checks a rewrite model can serve.
  static const int openRouterRewriteCheckTokens = 16;

  // === Groq Cloud Configuration ===

  static const String groqOrigin = 'https://api.groq.com';

  /// Groq transcription API endpoint (OpenAI-compatible).
  static const String groqTranscriptionEndpoint =
      '$groqOrigin/openai/v1/audio/transcriptions';

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

  /// The free tier takes files up to 25 MB (decimal); 23 MiB of PCM is
  /// 24.1 MB, leaving room for the WAV header and multipart framing (24 MiB
  /// was 25.2 MB and could be refused). About 12 min 34 s of audio.
  static const int groqMaxBufferBytes = 23 * 1024 * 1024;

  /// Free-tier rate limits (organisation-level).
  static const int groqMaxRpm = 20;
  static const int groqMaxRpd = 2000;

  /// HTTP timeout for the Groq REST call.
  static const Duration groqHttpTimeout = Duration(seconds: 30);

  /// Languages Groq's Whisper API accepts: ISO-639-1 code to English name.
  /// Codes from the Groq API error response (2026-03-24).
  static const Map<String, String> groqLanguageNames = {
    'af': 'Afrikaans',
    'am': 'Amharic',
    'ar': 'Arabic',
    'as': 'Assamese',
    'az': 'Azerbaijani',
    'ba': 'Bashkir',
    'be': 'Belarusian',
    'bg': 'Bulgarian',
    'bn': 'Bengali',
    'bo': 'Tibetan',
    'br': 'Breton',
    'bs': 'Bosnian',
    'ca': 'Catalan',
    'cs': 'Czech',
    'cy': 'Welsh',
    'da': 'Danish',
    'de': 'German',
    'el': 'Greek',
    'en': 'English',
    'es': 'Spanish',
    'et': 'Estonian',
    'eu': 'Basque',
    'fa': 'Persian',
    'fi': 'Finnish',
    'fo': 'Faroese',
    'fr': 'French',
    'gl': 'Galician',
    'gu': 'Gujarati',
    'ha': 'Hausa',
    'haw': 'Hawaiian',
    'he': 'Hebrew',
    'hi': 'Hindi',
    'hr': 'Croatian',
    'ht': 'Haitian Creole',
    'hu': 'Hungarian',
    'hy': 'Armenian',
    'id': 'Indonesian',
    'is': 'Icelandic',
    'it': 'Italian',
    'ja': 'Japanese',
    'jv': 'Javanese',
    'ka': 'Georgian',
    'kk': 'Kazakh',
    'km': 'Khmer',
    'kn': 'Kannada',
    'ko': 'Korean',
    'la': 'Latin',
    'lb': 'Luxembourgish',
    'ln': 'Lingala',
    'lo': 'Lao',
    'lt': 'Lithuanian',
    'lv': 'Latvian',
    'mg': 'Malagasy',
    'mi': 'Maori',
    'mk': 'Macedonian',
    'ml': 'Malayalam',
    'mn': 'Mongolian',
    'mr': 'Marathi',
    'ms': 'Malay',
    'mt': 'Maltese',
    'my': 'Burmese',
    'ne': 'Nepali',
    'nl': 'Dutch',
    'nn': 'Norwegian Nynorsk',
    'no': 'Norwegian',
    'oc': 'Occitan',
    'pa': 'Punjabi',
    'pl': 'Polish',
    'ps': 'Pashto',
    'pt': 'Portuguese',
    'ro': 'Romanian',
    'ru': 'Russian',
    'sa': 'Sanskrit',
    'sd': 'Sindhi',
    'si': 'Sinhala',
    'sk': 'Slovak',
    'sl': 'Slovenian',
    'sn': 'Shona',
    'so': 'Somali',
    'sq': 'Albanian',
    'sr': 'Serbian',
    'su': 'Sundanese',
    'sv': 'Swedish',
    'sw': 'Swahili',
    'ta': 'Tamil',
    'te': 'Telugu',
    'tg': 'Tajik',
    'th': 'Thai',
    'tk': 'Turkmen',
    'tl': 'Tagalog',
    'tr': 'Turkish',
    'tt': 'Tatar',
    'uk': 'Ukrainian',
    'ur': 'Urdu',
    'uz': 'Uzbek',
    'vi': 'Vietnamese',
    'yi': 'Yiddish',
    'yo': 'Yoruba',
    'yue': 'Cantonese',
    'zh': 'Chinese',
  };

  /// Validates a language code against the Groq supported set.
  /// Empty string is valid (means auto-detect).
  static bool isValidGroqLanguage(String code) =>
      code.isEmpty || groqLanguageNames.containsKey(code.trim().toLowerCase());

  /// Checks whether [model] is a supported Groq ASR model.
  static bool isValidGroqModel(String model) =>
      groqSupportedModels.contains(model.trim());

  // === Groq output styles ===

  /// Groq chat completions endpoint (OpenAI-compatible).
  static const String groqChatCompletionsEndpoint =
      '$groqOrigin/openai/v1/chat/completions';

  /// Default rewrite model. Verified active via scripts/benchmark_llm_providers.py (2026-09-05).
  /// Measured latency: TTFT ~217ms, Generation ~45ms, Total ~261ms on 27B parameters.
  static const String groqTransformModel = 'qwen/qwen3.8-27b';

  // === Output styles: the LLM rewrite, on any cloud source ===

  static const double transformTemperature = 0.1;

  /// Timeout scales with input so long dictations are not silently dropped
  /// to raw. total = base + perWord * wordCount, clamped to [base, max].
  static const Duration transformTimeoutBase = Duration(milliseconds: 1500);
  static const Duration transformTimeoutPerWord = Duration(milliseconds: 25);
  static const Duration transformTimeoutMax = Duration(seconds: 8);

  /// Output token ceiling scales with input: clamp(2 * estimatedInputTokens, min, max).
  /// Rough estimate: 1 token per 3 characters.
  static const int transformMinCompletionTokens = 128;
  static const int transformMaxCompletionTokens = 4096;
  static const int transformCharsPerToken = 3;

  /// Output length sanity bounds relative to input character count.
  /// Results outside this band are treated as hallucination/truncation and rejected.
  /// Set to 4.5 so a custom style may restructure and add markdown.
  static const double transformMinLengthRatio = 0.3;
  static const double transformMaxLengthRatio = 4.5;

  // === Custom Dictation Profiles ===

  /// Maximum character length of the user-authored portion of a custom
  /// system prompt. The shared preamble is prepended and is not counted.
  static const int customProfileMaxPromptLength = 2000;

  /// Maximum character length for custom profile display names.
  static const int customProfileMaxNameLength = 24;
}
