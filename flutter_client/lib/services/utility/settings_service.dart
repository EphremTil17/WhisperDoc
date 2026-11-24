import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/services/utility/secure_vault_service.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/dictation_profile.dart';
import 'package:flutter_client/logic/models/dictation_profile_spec.dart';
import 'package:flutter_client/logic/models/custom_profile.dart';
import 'package:flutter_client/logic/models/open_router_model_id.dart';
import 'package:flutter_client/logic/models/transcription_source.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsService extends ChangeNotifier {
  // Secure Vault Keys (sensitive data)
  static const String _vaultApiKeyKey = 'api_key';
  static const String _vaultGroqApiKey = 'groq_api_key';
  static const String _vaultGroqPrompt = 'groq_prompt';
  static const String _vaultOpenRouterApiKey = 'openrouter_api_key';

  // SharedPreferences Keys (non-sensitive data)
  static const String _keyServerUri = 'server_uri';
  static const String _keyGlobalHotkey = 'global_hotkey';
  static const String _keyHotkeyModifiers = 'hotkey_modifiers';
  static const String _keyHotkeyVKey = 'hotkey_vkey';
  static const String _keyMicrophoneId = 'microphone_id';
  static const String _keyMicrophoneLabel = 'microphone_label';
  static const String _keyAutoCopy = 'auto_copy';
  static const String _keyAutoPaste = 'auto_paste';
  static const String _keyShowVisualizer = 'show_visualizer';
  static const String _keyAnimateBackground = 'animate_background';
  static const String _keyIncognitoMode = 'incognito_mode';
  static const String _keyTranscriptionMode = 'transcription_mode';
  static const String _keyGroqLanguage = 'groq_language';
  static const String _keyGroqPrompt = 'groq_prompt';
  static const String _keyGroqModel = 'groq_model';
  static const String _keyOpenRouterModel = 'openrouter_model';
  static const String _keyOpenRouterZdr = 'openrouter_zdr';
  static const String _keyOpenRouterLanguage = 'openrouter_language';
  static const String _keyOpenRouterRewriteModel = 'openrouter_rewrite_model';
  static const String _keyDictationProfile = 'dictation_profile';
  static const String _keyCustomProfiles = 'custom_profiles_json';
  static const String _keyTrustedServers = 'trusted_servers';

  // Default Values (from AppConstants)
  static const String _defaultServerUri = AppConstants.defaultServerUri;
  static const String _defaultGlobalHotkey = AppConstants.defaultHotkeyDisplay;
  static const int _defaultHotkeyModifiers =
      AppConstants.defaultHotkeyModifiers;
  static const int _defaultHotkeyVKey = AppConstants.defaultHotkeyVKey;
  static const bool _defaultAutoCopy = true;
  static const bool _defaultAutoPaste = true;
  static const bool _defaultShowVisualizer = true;
  static const bool _defaultAnimateBackground = true;
  static const bool _defaultIncognitoMode = false;

  static const String _defaultGroqLanguage = '';
  static const String _defaultGroqPrompt = '';
  static const String _defaultGroqModel = AppConstants.groqDefaultModel;
  static const DictationProfile _defaultDictationProfile = DictationProfile.raw;
  static const int _jwtPartCount = 3;

  SharedPreferences? _prefs;
  SecureVaultService? _vault;
  bool _isInitialized = false;

  SettingsService({this._vault});

  String _serverUri = _defaultServerUri;
  String _globalHotkey = _defaultGlobalHotkey;
  int _hotkeyModifiers = _defaultHotkeyModifiers;
  int _hotkeyVKey = _defaultHotkeyVKey;
  String? _microphoneId;
  String? _microphoneLabel;
  bool _autoCopy = _defaultAutoCopy;
  bool _autoPaste = _defaultAutoPaste;
  bool _showVisualizer = _defaultShowVisualizer;
  bool _animateBackground = _defaultAnimateBackground;
  bool _incognitoMode = _defaultIncognitoMode;
  String? _apiKey;
  TranscriptionSource _source = TranscriptionSource.server;
  String? _groqApiKey;
  String _groqLanguage = _defaultGroqLanguage;
  String _groqPrompt = _defaultGroqPrompt;
  String _groqModel = _defaultGroqModel;
  String? _openRouterApiKey;
  String? _openRouterModel;
  bool _openRouterZdr = true;
  String _openRouterLanguage = '';
  String? _openRouterRewriteModel;
  DictationProfileSpec _dictationProfile = _defaultDictationProfile;
  List<CustomProfile> _customProfiles = [];
  Set<String> _trustedServers = {};
  String _appVersion = '...'; // Dynamic loading fallback

  String get appVersion => _appVersion;

  String get serverUri => _serverUri;
  String get globalHotkey => _globalHotkey;
  int get hotkeyModifiers => _hotkeyModifiers;
  int get hotkeyVKey => _hotkeyVKey;
  String? get microphoneId => _microphoneId;
  String? get microphoneLabel => _microphoneLabel;
  bool get autoCopy => _autoCopy;
  bool get autoPaste => _autoPaste;
  bool get showVisualizer => _showVisualizer;

  /// Whether the home screen's contour background moves; off, it is a still
  /// map that costs nothing after it is drawn.
  bool get animateBackground => _animateBackground;
  bool get incognitoMode => _incognitoMode;
  String? get cachedApiKey => _apiKey;
  SecureVaultService get vault => _requireVault();
  TranscriptionSource get transcriptionSource => _source;

  /// Output styles rewrite text through the cloud service's LLM, so only a
  /// cloud source offers them.
  bool get supportsStyles => _source.isCloud;
  String? get cachedGroqApiKey => _groqApiKey;
  String get groqLanguage => _groqLanguage;
  String get groqPrompt => _groqPrompt;
  String get groqModel => _groqModel;
  String? get cachedOpenRouterApiKey => _openRouterApiKey;

  /// The chosen OpenRouter speech model's id; null until one is chosen.
  String? get openRouterModel => _openRouterModel;

  /// Zero data retention: every OpenRouter request may only reach hosts that
  /// keep nothing. On unless the user turns it off.
  bool get openRouterZdr => _openRouterZdr;
  String get openRouterLanguage => _openRouterLanguage;

  /// The model the output styles rewrite with on OpenRouter: the user's
  /// own choice, else [AppConstants.openRouterTransformModel].
  String get openRouterRewriteModel =>
      _openRouterRewriteModel ?? AppConstants.openRouterTransformModel;

  /// The user replaced the default rewrite model.
  bool get hasCustomRewriteModel => _openRouterRewriteModel != null;

  /// The API key of the active cloud source; null for the server.
  String? get cloudApiKey => switch (_source) {
    TranscriptionSource.server => null,
    TranscriptionSource.groq => _groqApiKey,
    TranscriptionSource.openRouter => _openRouterApiKey,
  };

  bool get hasCloudKey => cloudApiKey?.isNotEmpty ?? false;
  DictationProfileSpec get dictationProfile => _dictationProfile;
  List<CustomProfile> get customProfiles => List.unmodifiable(_customProfiles);

  /// Servers, as `scheme://host:port`, the user agreed to send their
  /// sign-in to. The built-in server needs no entry.
  bool isTrustedServer(String origin) => _trustedServers.contains(origin);

  /// Returns the cached API key, fetching from vault if not yet loaded.
  /// Auto-detect token type: JWT (has 2 dots) vs Static API Key.
  static String getTokenLabel(String token) {
    if (token.contains('.') && token.split('.').length == _jwtPartCount) {
      return 'Access Token (JWT)';
    }

    return 'API Key';
  }

  Future<void> load() async {
    try {
      // Initialize secure vault (idempotent; safe for injected or new instances)
      final vault = _vault ?? SecureVaultService();
      await vault.initialize();
      _vault = vault;

      // Load shared preferences
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;

      // Load non-sensitive settings from SharedPreferences
      _serverUri = prefs.getString(_keyServerUri) ?? _defaultServerUri;
      _globalHotkey = prefs.getString(_keyGlobalHotkey) ?? _defaultGlobalHotkey;
      _hotkeyModifiers =
          prefs.getInt(_keyHotkeyModifiers) ?? _defaultHotkeyModifiers;
      _hotkeyVKey = prefs.getInt(_keyHotkeyVKey) ?? _defaultHotkeyVKey;
      _microphoneId = prefs.getString(_keyMicrophoneId);
      _microphoneLabel = prefs.getString(_keyMicrophoneLabel);
      _autoCopy = prefs.getBool(_keyAutoCopy) ?? _defaultAutoCopy;
      _autoPaste = prefs.getBool(_keyAutoPaste) ?? _defaultAutoPaste;
      _showVisualizer =
          prefs.getBool(_keyShowVisualizer) ?? _defaultShowVisualizer;
      _animateBackground =
          prefs.getBool(_keyAnimateBackground) ?? _defaultAnimateBackground;
      _incognitoMode =
          prefs.getBool(_keyIncognitoMode) ?? _defaultIncognitoMode;

      _trustedServers = {...?prefs.getStringList(_keyTrustedServers)};

      // Load API key from secure vault (cached in memory)
      _apiKey = await vault.retrieveCredential(_vaultApiKeyKey);

      _source = TranscriptionSource.fromStorageKey(
        prefs.getString(_keyTranscriptionMode),
      );

      // Groq
      _groqApiKey = await vault.retrieveCredential(_vaultGroqApiKey);
      _groqLanguage = prefs.getString(_keyGroqLanguage) ?? _defaultGroqLanguage;
      final storedGroqModel = prefs.getString(_keyGroqModel);
      _groqModel =
          (storedGroqModel != null &&
              AppConstants.isValidGroqModel(storedGroqModel))
          ? storedGroqModel.trim()
          : _defaultGroqModel;
      _groqPrompt =
          await vault.retrieveCredential(_vaultGroqPrompt) ??
          prefs.getString(_keyGroqPrompt) ??
          _defaultGroqPrompt;
      if (prefs.containsKey(_keyGroqPrompt)) {
        if (_groqPrompt.isNotEmpty) {
          await vault.storeCredential(_vaultGroqPrompt, _groqPrompt);
        }
        await prefs.remove(_keyGroqPrompt);
      }

      // OpenRouter
      _openRouterApiKey = await vault.retrieveCredential(
        _vaultOpenRouterApiKey,
      );
      _openRouterModel = prefs.getString(_keyOpenRouterModel);
      _openRouterZdr = prefs.getBool(_keyOpenRouterZdr) ?? true;
      _openRouterLanguage = prefs.getString(_keyOpenRouterLanguage) ?? '';
      final rewriteModel = prefs.getString(_keyOpenRouterRewriteModel);
      _openRouterRewriteModel =
          rewriteModel != null && OpenRouterModelId.isValid(rewriteModel)
          ? rewriteModel
          : null;

      final customJson = prefs.getString(_keyCustomProfiles);
      if (customJson != null && customJson.isNotEmpty) {
        try {
          final list = jsonDecode(customJson) as List<Object?>;
          final seenSlots = <String>{};
          final loaded = <CustomProfile>[];
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final profile = CustomProfile.tryFromJson(item);
              if (profile != null && seenSlots.add(profile.storageKey)) {
                loaded.add(profile);
              }
            }
          }
          _customProfiles = loaded;
        } catch (e) {
          LoggingService().warning('Failed to parse custom profiles JSON: $e');
          _customProfiles = [];
        }
      } else {
        _customProfiles = [];
      }

      _dictationProfile = supportsStyles
          ? _resolveProfile(prefs.getString(_keyDictationProfile))
          : DictationProfile.raw;

      // Load version info once
      final info = await PackageInfo.fromPlatform();
      _appVersion = info.version;

      _isInitialized = true;
      notifyListeners();
      LoggingService().info(
        'Settings loaded: URI=$_serverUri, Hotkey=$_globalHotkey, Incognito=$_incognitoMode',
      );
    } catch (e) {
      LoggingService().error('Failed to load settings', error: e);
      rethrow;
    }
  }

  Future<void> setAutoCopy(bool value) async {
    final prefs = _requirePrefs();
    if (_autoCopy == value) return;

    _autoCopy = value;
    // If auto-copy is disabled, auto-paste must also be disabled
    if (!value && _autoPaste) {
      _autoPaste = false;
      await prefs.setBool(_keyAutoPaste, false);
    }
    await prefs.setBool(_keyAutoCopy, value);
    notifyListeners();
    LoggingService().info('Auto-copy updated to: $value');
  }

  Future<void> setAutoPaste(bool value) async {
    final prefs = _requirePrefs();
    if (_autoPaste == value) return;

    _autoPaste = value;
    // If auto-paste is enabled, auto-copy must also be enabled
    if (value && !_autoCopy) {
      _autoCopy = true;
      await prefs.setBool(_keyAutoCopy, true);
    }
    await prefs.setBool(_keyAutoPaste, value);
    notifyListeners();
    LoggingService().info('Auto-paste updated to: $value');
  }

  Future<void> setShowVisualizer(bool value) async {
    final prefs = _requirePrefs();
    if (_showVisualizer == value) return;

    _showVisualizer = value;
    await prefs.setBool(_keyShowVisualizer, value);
    notifyListeners();
    LoggingService().info('Visualizer updated to: $value');
  }

  Future<void> setAnimateBackground(bool value) async {
    final prefs = _requirePrefs();
    if (_animateBackground == value) return;

    _animateBackground = value;
    await prefs.setBool(_keyAnimateBackground, value);
    notifyListeners();
    LoggingService().info('Animated background updated to: $value');
  }

  Future<void> setServerUri(String uri) async {
    final prefs = _requirePrefs();
    if (_serverUri == uri) return;

    _serverUri = uri;
    await prefs.setString(_keyServerUri, uri);
    notifyListeners();
    LoggingService().info('Server URI updated to: $uri');
  }

  /// Remembers that the user agreed to send their sign-in to [origin].
  Future<void> trustServer(String origin) async {
    final prefs = _requirePrefs();
    if (!_trustedServers.add(origin)) return;

    await prefs.setStringList(_keyTrustedServers, _trustedServers.toList());
    notifyListeners();
    LoggingService().info('Trusted server for sign-in: $origin');
  }

  /// Forgets every trusted server, for a sign-out or a new account.
  Future<void> clearTrustedServers() async {
    final prefs = _requirePrefs();
    if (_trustedServers.isEmpty) return;

    _trustedServers.clear();
    await prefs.remove(_keyTrustedServers);
    notifyListeners();
    LoggingService().info('Trusted servers cleared');
  }

  Future<void> setHotkey({
    required String display,
    required int modifiers,
    required int vKey,
  }) async {
    final prefs = _requirePrefs();

    _globalHotkey = display;
    _hotkeyModifiers = modifiers;
    _hotkeyVKey = vKey;

    await prefs.setString(_keyGlobalHotkey, display);
    await prefs.setInt(_keyHotkeyModifiers, modifiers);
    await prefs.setInt(_keyHotkeyVKey, vKey);

    notifyListeners();
    LoggingService().info(
      'Global hotkey updated to: $display (Mods: $modifiers, Key: $vKey)',
    );
  }

  Future<void> setMicrophoneSelection(String? id, String? label) async {
    final prefs = _requirePrefs();
    if (_microphoneId == id && _microphoneLabel == label) return;

    _microphoneId = id;
    _microphoneLabel = label;

    if (id == null) {
      await prefs.remove(_keyMicrophoneId);
      await prefs.remove(_keyMicrophoneLabel);
    } else {
      await prefs.setString(_keyMicrophoneId, id);
      if (label != null) {
        await prefs.setString(_keyMicrophoneLabel, label);
      }
    }
    notifyListeners();
    LoggingService().info('Microphone updated: ${label ?? "Default"}');
  }

  Future<void> setApiKey(String key) async {
    final vault = _requireVault();
    if (_apiKey == key) return;

    if (key.isEmpty) {
      _apiKey = null;
      await vault.deleteCredential(_vaultApiKeyKey);
    } else {
      _apiKey = key;
      await vault.storeCredential(_vaultApiKeyKey, key);
    }
    notifyListeners();
    LoggingService().info(
      key.isEmpty
          ? 'Backend API key removed'
          : '${getTokenLabel(key)} updated securely',
    );
  }

  Future<void> setIncognitoMode(bool value) async {
    final prefs = _requirePrefs();
    if (_incognitoMode == value) return;

    _incognitoMode = value;
    await prefs.setBool(_keyIncognitoMode, value);
    notifyListeners();
    LoggingService().info('Incognito mode updated to: $value');
  }

  Future<void> setTranscriptionSource(TranscriptionSource source) async {
    final prefs = _requirePrefs();
    if (_source == source) return;

    _source = source;
    await prefs.setString(_keyTranscriptionMode, source.storageKey);
    if (!supportsStyles && _dictationProfile != DictationProfile.raw) {
      _dictationProfile = DictationProfile.raw;
      await prefs.setString(
        _keyDictationProfile,
        DictationProfile.raw.storageKey,
      );
    }
    notifyListeners();
    LoggingService().info('Transcription source updated to: ${source.label}');
  }

  // === Groq ===

  Future<void> setGroqApiKey(String key) async {
    final vault = _requireVault();
    if (_groqApiKey == key) return;

    if (key.isEmpty) {
      _groqApiKey = null;
      await vault.deleteCredential(_vaultGroqApiKey);
    } else {
      _groqApiKey = key;
      await vault.storeCredential(_vaultGroqApiKey, key);
    }
    notifyListeners();
    LoggingService().info('Groq API key updated securely');
  }

  Future<void> setGroqLanguage(String language) async {
    final prefs = _requirePrefs();
    if (_groqLanguage == language) return;

    _groqLanguage = language;
    await prefs.setString(_keyGroqLanguage, language);
    notifyListeners();
    LoggingService().info('Groq language updated to: $language');
  }

  Future<void> setGroqPrompt(String prompt) async {
    final vault = _requireVault();
    if (_groqPrompt == prompt) return;

    _groqPrompt = prompt;
    if (prompt.isEmpty) {
      await vault.deleteCredential(_vaultGroqPrompt);
    } else {
      await vault.storeCredential(_vaultGroqPrompt, prompt);
    }
    notifyListeners();
    LoggingService().info('Groq prompt updated');
  }

  Future<void> setGroqModel(String model) async {
    final prefs = _requirePrefs();
    final normalizedModel = AppConstants.isValidGroqModel(model)
        ? model.trim()
        : _defaultGroqModel;
    if (_groqModel == normalizedModel) return;

    _groqModel = normalizedModel;
    await prefs.setString(_keyGroqModel, normalizedModel);
    notifyListeners();
    LoggingService().info('Groq model updated to: $normalizedModel');
  }

  // === OpenRouter ===

  Future<void> setOpenRouterApiKey(String key) async {
    final vault = _requireVault();
    if (_openRouterApiKey == key) return;

    if (key.isEmpty) {
      _openRouterApiKey = null;
      await vault.deleteCredential(_vaultOpenRouterApiKey);
    } else {
      _openRouterApiKey = key;
      await vault.storeCredential(_vaultOpenRouterApiKey, key);
    }
    notifyListeners();
    LoggingService().info('OpenRouter API key updated securely');
  }

  Future<void> setOpenRouterModel(String model) async {
    final prefs = _requirePrefs();
    if (_openRouterModel == model) return;

    _openRouterModel = model;
    await prefs.setString(_keyOpenRouterModel, model);
    notifyListeners();
    LoggingService().info('OpenRouter model updated to: $model');
  }

  Future<void> setOpenRouterZdr(bool value) async {
    final prefs = _requirePrefs();
    if (_openRouterZdr == value) return;

    _openRouterZdr = value;
    await prefs.setBool(_keyOpenRouterZdr, value);
    notifyListeners();
    LoggingService().info('OpenRouter zero data retention: $value');
  }

  Future<void> setOpenRouterLanguage(String language) async {
    final prefs = _requirePrefs();
    if (_openRouterLanguage == language) return;

    _openRouterLanguage = language;
    await prefs.setString(_keyOpenRouterLanguage, language);
    notifyListeners();
    LoggingService().info('OpenRouter language updated to: $language');
  }

  /// Rewrites with [model] from now on; empty, or the default itself,
  /// goes back to the default.
  Future<void> setOpenRouterRewriteModel(String model) async {
    final prefs = _requirePrefs();
    final custom =
        model.isEmpty || model == AppConstants.openRouterTransformModel
        ? null
        : model;
    if (_openRouterRewriteModel == custom) return;

    _openRouterRewriteModel = custom;
    if (custom == null) {
      await prefs.remove(_keyOpenRouterRewriteModel);
    } else {
      await prefs.setString(_keyOpenRouterRewriteModel, custom);
    }
    notifyListeners();
    LoggingService().info('OpenRouter rewrite model: $openRouterRewriteModel');
  }

  DictationProfileSpec _resolveProfile(String? key) {
    if (key == null) return DictationProfile.raw;
    final builtIn = DictationProfile.tryFromStorageKey(key);
    if (builtIn != null) return builtIn;
    for (final c in _customProfiles) {
      if (c.storageKey == key) return c;
    }

    return DictationProfile.raw;
  }

  /// Returns the first unused slot key from [CustomProfile.slotKeys],
  /// or null when all 3 slots are occupied.
  String? nextFreeCustomSlot() {
    final used = _customProfiles.map((p) => p.storageKey).toSet();
    for (final slot in CustomProfile.slotKeys) {
      if (!used.contains(slot)) return slot;
    }

    return null;
  }

  /// Upserts a custom profile by its [CustomProfile.storageKey].
  Future<void> saveCustomProfile(CustomProfile profile) async {
    final prefs = _requirePrefs();
    if (!CustomProfile.slotKeys.contains(profile.storageKey)) {
      throw ArgumentError(
        'Invalid custom profile slot key: ${profile.storageKey}',
      );
    }
    if (profile.name.trim().isEmpty) {
      throw ArgumentError('Custom profile name cannot be empty');
    }
    if (profile.userPrompt.trim().isEmpty) {
      throw ArgumentError('Custom profile prompt cannot be empty');
    }
    if (profile.userPrompt.length > AppConstants.customProfileMaxPromptLength) {
      throw ArgumentError('Custom profile prompt exceeds max length');
    }

    final index = _customProfiles.indexWhere(
      (p) => p.storageKey == profile.storageKey,
    );
    if (index >= 0) {
      _customProfiles[index] = profile;
    } else {
      _customProfiles.add(profile);
    }

    await prefs.setString(
      _keyCustomProfiles,
      jsonEncode(_customProfiles.map((p) => p.toJson()).toList()),
    );

    _dictationProfile = _resolveProfile(_dictationProfile.storageKey);
    notifyListeners();
    LoggingService().info(
      'Saved custom profile: ${profile.label} (${profile.storageKey})',
    );
  }

  /// Deletes a custom profile by its [storageKey] and frees the slot.
  /// If the deleted profile was active, resets active profile to [DictationProfile.raw].
  Future<void> deleteCustomProfile(String storageKey) async {
    final prefs = _requirePrefs();
    _customProfiles.removeWhere((p) => p.storageKey == storageKey);
    await prefs.setString(
      _keyCustomProfiles,
      jsonEncode(_customProfiles.map((p) => p.toJson()).toList()),
    );

    if (_dictationProfile.storageKey == storageKey) {
      _dictationProfile = DictationProfile.raw;
      await prefs.setString(
        _keyDictationProfile,
        DictationProfile.raw.storageKey,
      );
    }

    notifyListeners();
    LoggingService().info('Deleted custom profile: $storageKey');
  }

  Future<void> setDictationProfile(DictationProfileSpec profile) async {
    final prefs = _requirePrefs();
    final resolved = supportsStyles ? profile : DictationProfile.raw;
    if (_dictationProfile.storageKey == resolved.storageKey) return;

    _dictationProfile = resolved;
    await prefs.setString(_keyDictationProfile, resolved.storageKey);
    notifyListeners();
    LoggingService().info(
      'Dictation profile updated to: ${resolved.label} (${resolved.storageKey})',
    );
  }

  SharedPreferences _requirePrefs() {
    final prefs = _prefs;
    if (!_isInitialized || prefs == null) {
      throw StateError('SettingsService not initialized. Call load() first.');
    }

    return prefs;
  }

  SecureVaultService _requireVault() {
    final vault = _vault;
    if (!_isInitialized || vault == null) {
      throw StateError('SettingsService not initialized. Call load() first.');
    }

    return vault;
  }
}
