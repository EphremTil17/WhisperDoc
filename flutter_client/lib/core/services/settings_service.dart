import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logging_service.dart';

class SettingsService extends ChangeNotifier {
  static const String _keyServerUri = 'server_uri';
  static const String _keyGlobalHotkey = 'global_hotkey';
  static const String _keyMicrophoneId = 'microphone_id';

  // Default Values
  static const String _defaultServerUri = 'ws://localhost:9989/ws';
  static const String _defaultGlobalHotkey = 'Ctrl+Alt+W';

  late SharedPreferences _prefs;
  bool _isInitialized = false;

  String _serverUri = _defaultServerUri;
  String _globalHotkey = _defaultGlobalHotkey;
  String? _microphoneId;

  String get serverUri => _serverUri;
  String get globalHotkey => _globalHotkey;
  String? get microphoneId => _microphoneId;

  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _serverUri = _prefs.getString(_keyServerUri) ?? _defaultServerUri;
      _globalHotkey =
          _prefs.getString(_keyGlobalHotkey) ?? _defaultGlobalHotkey;
      _microphoneId = _prefs.getString(_keyMicrophoneId);

      _isInitialized = true;
      notifyListeners();
      LoggingService().info(
        'Settings loaded: URI=$_serverUri, Hotkey=$_globalHotkey',
      );
    } catch (e) {
      LoggingService().error('Failed to load settings', error: e);
    }
  }

  Future<void> setServerUri(String uri) async {
    _ensureInitialized();
    if (_serverUri == uri) return;

    _serverUri = uri;
    await _prefs.setString(_keyServerUri, uri);
    notifyListeners();
    LoggingService().info('Server URI updated to: $uri');
  }

  Future<void> setGlobalHotkey(String hotkey) async {
    _ensureInitialized();
    if (_globalHotkey == hotkey) return;

    _globalHotkey = hotkey;
    await _prefs.setString(_keyGlobalHotkey, hotkey);
    notifyListeners();
    LoggingService().info('Global hotkey updated to: $hotkey');
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
