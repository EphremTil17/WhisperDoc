import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';

enum UpdateStatus { upToDate, advisory, required }

class UpdateService extends ChangeNotifier {
  final WebSocketService _wsService;
  UpdateStatus _status = UpdateStatus.upToDate;
  String? _latestDownloadUrl;

  UpdateStatus get status => _status;
  String? get latestDownloadUrl => _latestDownloadUrl;

  DateTime? _lastGithubCheck;
  String? _lastCheckedMin;
  String? _lastCheckedServer;

  UpdateService(this._wsService) {
    _wsService.addListener(_onServiceStateChanged);
    unawaited(_checkVersion(forceGithub: true));
  }

  void _onServiceStateChanged() {
    final error = _wsService.lastHandshakeError;
    if (error != null && error.toLowerCase().contains('update required')) {
      setStatus(UpdateStatus.required);
      return;
    }

    // Only re-evaluate if the version requirements from the server have actually arrived or changed
    final currentMin = _wsService.backendMinVersion;
    final currentServer = _wsService.backendServerVersion;

    if (currentMin != _lastCheckedMin || currentServer != _lastCheckedServer) {
      _lastCheckedMin = currentMin;
      _lastCheckedServer = currentServer;
      unawaited(_checkVersion());
    }
  }

  void setStatus(UpdateStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      notifyListeners();
    }
  }

  String? _githubVersion;

  Future<void> _checkVersion({bool forceGithub = false}) async {
    final info = await PackageInfo.fromPlatform();
    final current = info.version;
    final min = _wsService.backendMinVersion;
    final sec = _wsService.backendSecVersion;
    final server = _wsService.backendServerVersion;

    if (min != null && _isVersionLower(current, min)) {
      _status = UpdateStatus.required;
    } else if (sec != null && _isVersionLower(current, sec)) {
      _status = UpdateStatus.advisory;
    } else if (server != null && _isVersionLower(current, server)) {
      _status = UpdateStatus.advisory;
    } else if (_githubVersion != null &&
        _isVersionLower(current, _githubVersion!)) {
      _status = UpdateStatus.advisory;
    } else {
      _status = UpdateStatus.upToDate;
    }

    // Rate-limited GitHub discovery (6 hour cooldown)
    final now = DateTime.now();
    final bool isCooldownExpired =
        _lastGithubCheck == null ||
        now.difference(_lastGithubCheck!).inHours >= 6;

    if (forceGithub ||
        (isCooldownExpired && _status != UpdateStatus.upToDate)) {
      unawaited(_discoverLatestAsset());
    }

    notifyListeners();
  }

  /// Queries GitHub API to find the latest version and the .exe asset URL.
  Future<void> _discoverLatestAsset() async {
    _lastGithubCheck = DateTime.now();
    try {
      final response = await http.get(
        Uri.parse(AppConstants.githubApiLatestRelease),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final tagName = (data['tag_name'] as String).replaceAll('v', '');
        _githubVersion = tagName;

        final assets = data['assets'] as List<dynamic>;
        final exeAsset = assets.firstWhere(
          (asset) => (asset['name'] as String).toLowerCase().endsWith('.exe'),
          orElse: () => null,
        );

        if (exeAsset != null) {
          _latestDownloadUrl = exeAsset['browser_download_url'] as String;
        }

        unawaited(_checkVersion());
      }
    } catch (_) {
      // Fail silently to avoid UI noise
    }
  }

  /// Simple SemVer comparison (major.minor.patch)
  bool _isVersionLower(String current, String target) {
    try {
      // Helper to strip build numbers or pre-release tags (e.g., 2.18.0+1 -> 2.18.0)
      String clean(String v) => v.split('+')[0].split('-')[0];

      final currentParts = clean(current).split('.').map(int.parse).toList();
      final targetParts = clean(target).split('.').map(int.parse).toList();

      for (var i = 0; i < 3; i++) {
        final c = i < currentParts.length ? currentParts[i] : 0;
        final t = i < targetParts.length ? targetParts[i] : 0;
        if (c < t) return true;
        if (c > t) return false;
      }
      return false;
    } catch (_) {
      return false; // Safely fail-closed if strings are malformed
    }
  }
}
