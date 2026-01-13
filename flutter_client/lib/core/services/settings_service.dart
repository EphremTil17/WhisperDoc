import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_client/core/services/logging_service.dart';
import 'package:flutter_client/core/constants/app_constants.dart';

class SettingsService extends ChangeNotifier {
  static const String _keyServerUri = 'server_uri';
  static const String _keyGlobalHotkey = 'global_hotkey';
  static const String _keyHotkeyModifiers = 'hotkey_modifiers';
  static const String _keyHotkeyVKey = 'hotkey_vkey';
  static const String _keyMicrophoneId = 'microphone_id';
  static const String _keyAutoCopy = 'auto_copy';
  static const String _keyAutoPaste = 'auto_paste';
  static const String _keyShowVisualizer = 'show_visualizer';

  // Default Values (from AppConstants)
  static const String _defaultServerUri = AppConstants.defaultServerUri;
  static const String _defaultGlobalHotkey = AppConstants.defaultHotkeyDisplay;
  static const int _defaultHotkeyModifiers =
      AppConstants.defaultHotkeyModifiers;
  static const int _defaultHotkeyVKey = AppConstants.defaultHotkeyVKey;
  static const bool _defaultAutoCopy = true;
  static const bool _defaultAutoPaste = false;
  static const bool _defaultShowVisualizer = true;

  late SharedPreferences _prefs;
  bool _isInitialized = false;

  String _serverUri = _defaultServerUri;
  String _globalHotkey = _defaultGlobalHotkey;
  int _hotkeyModifiers = _defaultHotkeyModifiers;
  int _hotkeyVKey = _defaultHotkeyVKey;
  String? _microphoneId;
  bool _autoCopy = _defaultAutoCopy;
  bool _autoPaste = _defaultAutoPaste;
  bool _showVisualizer = _defaultShowVisualizer;

  String get serverUri => _serverUri;
  String get globalHotkey => _globalHotkey;
  int get hotkeyModifiers => _hotkeyModifiers;
  int get hotkeyVKey => _hotkeyVKey;
  String? get microphoneId => _microphoneId;
  bool get autoCopy => _autoCopy;
  bool get autoPaste => _autoPaste;
  bool get showVisualizer => _showVisualizer;

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
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

      _isInitialized = true;
      notifyListeners();
      LoggingService().info(
        'Settings loaded: URI=$_serverUri, Hotkey=$_globalHotkey, AutoCopy=$_autoCopy, AutoPaste=$_autoPaste',
      );
    } catch (e) {
      LoggingService().error('Failed to load settings', error: e);
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

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw Exception('SettingsService not initialized. Call load() first.');
    }
  }
}
