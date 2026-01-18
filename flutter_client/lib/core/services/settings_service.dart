import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_client/core/services/logging_service.dart';
import 'package:flutter_client/core/services/secure_vault_service.dart';
import 'package:flutter_client/core/constants/app_constants.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsService extends ChangeNotifier {
  // Secure Vault Keys (sensitive data)
  static const String _vaultApiKeyKey = 'api_key';

  // SharedPreferences Keys (non-sensitive data)
  static const String _keyServerUri = 'server_uri';
  static const String _keyGlobalHotkey = 'global_hotkey';
  static const String _keyHotkeyModifiers = 'hotkey_modifiers';
  static const String _keyHotkeyVKey = 'hotkey_vkey';
  static const String _keyMicrophoneId = 'microphone_id';
  static const String _keyAutoCopy = 'auto_copy';
  static const String _keyAutoPaste = 'auto_paste';
  static const String _keyShowVisualizer = 'show_visualizer';
  static const String _keyIncognitoMode = 'incognito_mode';

  // Default Values (from AppConstants)
  static const String _defaultServerUri = AppConstants.defaultServerUri;
  static const String _defaultGlobalHotkey = AppConstants.defaultHotkeyDisplay;
  static const int _defaultHotkeyModifiers =
      AppConstants.defaultHotkeyModifiers;
  static const int _defaultHotkeyVKey = AppConstants.defaultHotkeyVKey;
  static const bool _defaultAutoCopy = true;
  static const bool _defaultAutoPaste = false;
  static const bool _defaultShowVisualizer = true;
  static const bool _defaultIncognitoMode = false;

  late SharedPreferences _prefs;
  late SecureVaultService _vault;
  bool _isInitialized = false;

  String _serverUri = _defaultServerUri;
  String _globalHotkey = _defaultGlobalHotkey;
  int _hotkeyModifiers = _defaultHotkeyModifiers;
  int _hotkeyVKey = _defaultHotkeyVKey;
  String? _microphoneId;
  bool _autoCopy = _defaultAutoCopy;
  bool _autoPaste = _defaultAutoPaste;
  bool _showVisualizer = _defaultShowVisualizer;
  bool _incognitoMode = _defaultIncognitoMode;
  String? _apiKey;
  String _appVersion = '2.11.0'; // Default fallback

  String get appVersion => _appVersion;

  String get serverUri => _serverUri;
  String get globalHotkey => _globalHotkey;
  int get hotkeyModifiers => _hotkeyModifiers;
  int get hotkeyVKey => _hotkeyVKey;
  String? get microphoneId => _microphoneId;
  bool get autoCopy => _autoCopy;
  bool get autoPaste => _autoPaste;
  bool get showVisualizer => _showVisualizer;
  bool get incognitoMode => _incognitoMode;
  String? get cachedApiKey => _apiKey;
  SecureVaultService get vault => _vault;

  /// Loads settings from SharedPreferences and SecureVault.
  Future<String?> getApiKey() async {
    _ensureInitialized();
    _apiKey ??= await _vault.retrieveCredential(_vaultApiKeyKey);
    return _apiKey;
  }

  /// Auto-detect token type: JWT (has 2 dots) vs Static API Key
  String getTokenLabel(String token) {
    if (token.contains('.') && token.split('.').length == 3) {
      return 'Access Token (JWT)';
    }
    return 'API Key';
  }

  Future<void> load() async {
    try {
      // Initialize secure vault first
      _vault = SecureVaultService();
      await _vault.initialize();

      // Load shared preferences
      _prefs = await SharedPreferences.getInstance();

      // Load non-sensitive settings from SharedPreferences
      _serverUri = _prefs.getString(_keyServerUri) ?? _defaultServerUri;
      _globalHotkey =
          _prefs.getString(_keyGlobalHotkey) ?? _defaultGlobalHotkey;
      _hotkeyModifiers =
          _prefs.getInt(_keyHotkeyModifiers) ?? _defaultHotkeyModifiers;
      _hotkeyVKey = _prefs.getInt(_keyHotkeyVKey) ?? _defaultHotkeyVKey;
      _microphoneId = _prefs.getString(_keyMicrophoneId);
      _autoCopy = _prefs.getBool(_keyAutoCopy) ?? _defaultAutoCopy;
      _autoPaste = _prefs.getBool(_keyAutoPaste) ?? _defaultAutoPaste;
      _showVisualizer =
          _prefs.getBool(_keyShowVisualizer) ?? _defaultShowVisualizer;
      _incognitoMode =
          _prefs.getBool(_keyIncognitoMode) ?? _defaultIncognitoMode;

      // Load API key from secure vault (cached in memory)
      _apiKey = await _vault.retrieveCredential(_vaultApiKeyKey);

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
    _ensureInitialized();
    if (_autoCopy == value) return;

    _autoCopy = value;
    // If auto-copy is disabled, auto-paste must also be disabled
    if (!value && _autoPaste) {
      _autoPaste = false;
      await _prefs.setBool(_keyAutoPaste, false);
    }
    await _prefs.setBool(_keyAutoCopy, value);
    notifyListeners();
    LoggingService().info('Auto-copy updated to: $value');
  }

  Future<void> setAutoPaste(bool value) async {
    _ensureInitialized();
    if (_autoPaste == value) return;

    _autoPaste = value;
    // If auto-paste is enabled, auto-copy must also be enabled
    if (value && !_autoCopy) {
      _autoCopy = true;
      await _prefs.setBool(_keyAutoCopy, true);
    }
    await _prefs.setBool(_keyAutoPaste, value);
    notifyListeners();
    LoggingService().info('Auto-paste updated to: $value');
  }

  Future<void> setShowVisualizer(bool value) async {
    _ensureInitialized();
    if (_showVisualizer == value) return;

    _showVisualizer = value;
    await _prefs.setBool(_keyShowVisualizer, value);
    notifyListeners();
    LoggingService().info('Visualizer updated to: $value');
  }

  Future<void> setServerUri(String uri) async {
    _ensureInitialized();
    if (_serverUri == uri) return;

    _serverUri = uri;
    await _prefs.setString(_keyServerUri, uri);
    notifyListeners();
    LoggingService().info('Server URI updated to: $uri');
  }

  Future<void> setHotkey({
    required String display,
    required int modifiers,
    required int vKey,
  }) async {
    _ensureInitialized();

    _globalHotkey = display;
    _hotkeyModifiers = modifiers;
    _hotkeyVKey = vKey;

    await _prefs.setString(_keyGlobalHotkey, display);
    await _prefs.setInt(_keyHotkeyModifiers, modifiers);
    await _prefs.setInt(_keyHotkeyVKey, vKey);

    notifyListeners();
    LoggingService().info(
      'Global hotkey updated to: $display (Mods: $modifiers, Key: $vKey)',
    );
  }

  Future<void> setMicrophoneId(String? id) async {
    _ensureInitialized();
    if (_microphoneId == id) return;

    _microphoneId = id;
    if (id == null) {
      await _prefs.remove(_keyMicrophoneId);
    } else {
      await _prefs.setString(_keyMicrophoneId, id);
    }
    notifyListeners();
    LoggingService().info('Microphone ID updated to: $id');
  }

  Future<void> setApiKey(String key) async {
    _ensureInitialized();
    if (_apiKey == key) return;

    _apiKey = key;
    await _vault.storeCredential(_vaultApiKeyKey, key);
    notifyListeners();
    final label = getTokenLabel(key);
    LoggingService().info('$label updated securely');
  }

  Future<void> setIncognitoMode(bool value) async {
    _ensureInitialized();
    if (_incognitoMode == value) return;

    _incognitoMode = value;
    await _prefs.setBool(_keyIncognitoMode, value);
    notifyListeners();
    LoggingService().info('Incognito mode updated to: $value');
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw Exception('SettingsService not initialized. Call load() first.');
    }
  }
}
