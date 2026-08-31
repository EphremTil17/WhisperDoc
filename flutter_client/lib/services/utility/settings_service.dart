import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/services/utility/secure_vault_service.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/logic/models/dictation_profile.dart';
import 'package:flutter_client/logic/models/dictation_profile_spec.dart';
import 'package:flutter_client/logic/models/custom_profile.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsService extends ChangeNotifier {
  // Secure Vault Keys (sensitive data)
  static const String _vaultApiKeyKey = 'api_key';
  static const String _vaultGroqApiKey = 'groq_api_key';
  static const String _vaultGroqPrompt = 'groq_prompt';

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
  static const String _keyIncognitoMode = 'incognito_mode';
  static const String _keyTranscriptionMode = 'transcription_mode';
  static const String _keyGroqLanguage = 'groq_language';
  static const String _keyGroqPrompt = 'groq_prompt';
  static const String _keyGroqModel = 'groq_model';
  static const String _keyDictationProfile = 'dictation_profile';
  static const String _keyCustomProfiles = 'custom_profiles_json';

  // Default Values (from AppConstants)
  static const String _defaultServerUri = AppConstants.defaultServerUri;
  static const String _defaultGlobalHotkey = AppConstants.defaultHotkeyDisplay;
  static const int _defaultHotkeyModifiers =
      AppConstants.defaultHotkeyModifiers;
  static const int _defaultHotkeyVKey = AppConstants.defaultHotkeyVKey;
  static const bool _defaultAutoCopy = true;
  static const bool _defaultAutoPaste = true;
  static const bool _defaultShowVisualizer = true;
  static const bool _defaultIncognitoMode = false;
  static const String _defaultTranscriptionMode = 'backend';
  static const String _defaultGroqLanguage = '';
  static const String _defaultGroqPrompt = '';
  static const String _defaultGroqModel = AppConstants.groqDefaultModel;
  static const DictationProfile _defaultDictationProfile = DictationProfile.raw;
  static const int _jwtPartCount = 3;

  SharedPreferences? _prefs;
  SecureVaultService? _vault;
  bool _isInitialized = false;

  SettingsService({SecureVaultService? vault}) : _vault = vault;

  String _serverUri = _defaultServerUri;
  String _globalHotkey = _defaultGlobalHotkey;
  int _hotkeyModifiers = _defaultHotkeyModifiers;
  int _hotkeyVKey = _defaultHotkeyVKey;
  String? _microphoneId;
  String? _microphoneLabel;
  bool _autoCopy = _defaultAutoCopy;
  bool _autoPaste = _defaultAutoPaste;
  bool _showVisualizer = _defaultShowVisualizer;
  bool _incognitoMode = _defaultIncognitoMode;
  String? _apiKey;
  String _transcriptionMode = _defaultTranscriptionMode;
  String? _groqApiKey;
  String _groqLanguage = _defaultGroqLanguage;
  String _groqPrompt = _defaultGroqPrompt;
  String _groqModel = _defaultGroqModel;
  DictationProfileSpec _dictationProfile = _defaultDictationProfile;
  List<CustomProfile> _customProfiles = [];
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
  bool get incognitoMode => _incognitoMode;
  String? get cachedApiKey => _apiKey;
  SecureVaultService get vault => _requireVault();
  String get transcriptionMode => _transcriptionMode;
  bool get isGroqMode => _transcriptionMode == 'groq';
  String? get cachedGroqApiKey => _groqApiKey;
  String get groqLanguage => _groqLanguage;
  String get groqPrompt => _groqPrompt;
  String get groqModel => _groqModel;
  DictationProfileSpec get dictationProfile => _dictationProfile;
  List<CustomProfile> get customProfiles => List.unmodifiable(_customProfiles);

  /// Returns the cached API key, fetching from vault if not yet loaded.
  Future<String?> getApiKey() async {
    final vault = _requireVault();
    _apiKey ??= await vault.retrieveCredential(_vaultApiKeyKey);

    return _apiKey;
  }

  /// Auto-detect token type: JWT (has 2 dots) vs Static API Key.
  String getTokenLabel(String token) {
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
      _incognitoMode =
          prefs.getBool(_keyIncognitoMode) ?? _defaultIncognitoMode;

      // Load API key from secure vault (cached in memory)
      _apiKey = await vault.retrieveCredential(_vaultApiKeyKey);

      // Load Groq Cloud settings
      _transcriptionMode =
          prefs.getString(_keyTranscriptionMode) ?? _defaultTranscriptionMode;
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

      _dictationProfile = isGroqMode
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

  Future<void> setServerUri(String uri) async {
    final prefs = _requirePrefs();
    if (_serverUri == uri) return;

    _serverUri = uri;
    await prefs.setString(_keyServerUri, uri);
    notifyListeners();
    LoggingService().info('Server URI updated to: $uri');
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

  // === Groq Cloud Setters ===

  /// Returns the cached Groq API key, fetching from vault if not yet loaded.
  Future<String?> getGroqApiKey() async {
    final vault = _requireVault();
    _groqApiKey ??= await vault.retrieveCredential(_vaultGroqApiKey);

    return _groqApiKey;
  }

  Future<void> setTranscriptionMode(String mode) async {
    final prefs = _requirePrefs();
    if (_transcriptionMode == mode) return;

    _transcriptionMode = mode;
    await prefs.setString(_keyTranscriptionMode, mode);
    if (!isGroqMode && _dictationProfile != DictationProfile.raw) {
      _dictationProfile = DictationProfile.raw;
      await prefs.setString(
        _keyDictationProfile,
        DictationProfile.raw.storageKey,
      );
    }
    notifyListeners();
    LoggingService().info('Transcription mode updated to: $mode');
  }

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
    final prefs = _requirePrefs();
    final vault = _requireVault();
    if (_groqPrompt == prompt) return;

    _groqPrompt = prompt;
    if (prompt.isEmpty) {
      await vault.deleteCredential(_vaultGroqPrompt);
    } else {
      await vault.storeCredential(_vaultGroqPrompt, prompt);
    }
    if (prefs.containsKey(_keyGroqPrompt)) {
      await prefs.remove(_keyGroqPrompt);
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

  DictationProfileSpec _resolveProfile(String? key) {
    if (key == null) return DictationProfile.raw;
    for (final p in DictationProfile.values) {
      if (p.storageKey == key) return p;
    }
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
    final resolved = isGroqMode ? profile : DictationProfile.raw;
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
