import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';

class UpdateService extends ChangeNotifier {
  static const int _githubCooldownHours = 6;
  static const int _httpOkStatusCode = 200;
  static const int _semverPartsToCompare = 3;
  static const Duration _githubTimeout = Duration(seconds: 10);
  static const int _httpsPort = 443;

  /// Verifies that a release or installer URL is an HTTPS page or asset of
  /// this app's own GitHub repository before the OS shell opens it.
  ///
  /// Only github.com: the API's `browser_download_url` always points there,
  /// and the asset CDN hosts are redirect targets the browser follows on its
  /// own. Allowing them would let a forged response name any user's asset.
  static bool isTrustedReleaseUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return false;
    if (uri.userInfo.isNotEmpty || uri.port != _httpsPort) return false;
    if (uri.host.toLowerCase() != 'github.com') return false;
    final repoPrefix = '/${AppConstants.githubRepo.toLowerCase()}/';

    return uri.path.toLowerCase().startsWith(repoPrefix);
  }

  final WebSocketService _wsService;
  UpdateStatus _status = UpdateStatus.upToDate;
  String? _latestDownloadUrl;
  DateTime? _lastGithubCheck;
  String? _lastCheckedMin;
  String? _lastCheckedServer;
  String? _githubVersion;
  bool _disposed = false;

  UpdateStatus get status => _status;
  String? get latestDownloadUrl => _latestDownloadUrl;
  String? get latestVersion => _githubVersion;

  UpdateService(this._wsService) {
    _wsService.addListener(_onServiceStateChanged);
    unawaited(_checkVersion(forceGithub: true));
  }

  void setStatus(UpdateStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      notifyListeners();
    }
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

  Future<void> _checkVersion({bool forceGithub = false}) async {
    final info = await PackageInfo.fromPlatform();
    if (_disposed) return;
    final current = info.version;
    final min = _wsService.backendMinVersion;
    final sec = _wsService.backendSecVersion;
    final server = _wsService.backendServerVersion;

    final ghVersion = _githubVersion;

    if (min != null && _isVersionLower(current, min)) {
      _status = UpdateStatus.required;
    } else if (sec != null && _isVersionLower(current, sec)) {
      _status = UpdateStatus.advisory;
    } else if (server != null && _isVersionLower(current, server)) {
      _status = UpdateStatus.advisory;
    } else if (ghVersion != null && _isVersionLower(current, ghVersion)) {
      _status = UpdateStatus.advisory;
    } else {
      _status = UpdateStatus.upToDate;
    }

    // Rate-limited GitHub discovery (6 hour cooldown)
    final now = DateTime.now();
    final lastCheck = _lastGithubCheck;
    final bool isCooldownExpired =
        lastCheck == null ||
        now.difference(lastCheck).inHours >= _githubCooldownHours;

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
      final response = await http
          .get(Uri.parse(AppConstants.githubApiLatestRelease))
          .timeout(_githubTimeout);
      if (_disposed) return;

      if (response.statusCode == _httpOkStatusCode) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final tagName = (data['tag_name'] as String).replaceAll('v', '');
        _githubVersion = tagName;

        final assetsRaw = data['assets'];
        Map<String, Object?>? exeAsset;
        if (assetsRaw is List) {
          for (final assetRaw in assetsRaw) {
            if (assetRaw is Map) {
              final asset = Map<String, Object?>.from(assetRaw);
              final name = asset['name'];
              if (name is String && name.toLowerCase().endsWith('.exe')) {
                exeAsset = asset;
                break;
              }
            }
          }
        }

        if (exeAsset != null) {
          final candidate = exeAsset['browser_download_url'];
          if (candidate is String && isTrustedReleaseUrl(candidate)) {
            _latestDownloadUrl = candidate;
          }
        }

        unawaited(_checkVersion());
      }
    } catch (_) {
      // Fail silently to avoid UI noise
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _wsService.removeListener(_onServiceStateChanged);
    super.dispose();
  }

  /// Simple SemVer comparison (major.minor.patch)
  bool _isVersionLower(String current, String target) {
    try {
      // Helper to strip build numbers or pre-release tags (e.g., 2.18.0+1 -> 2.18.0)
      String clean(String v) => v.split('+').first.split('-').first;

      final currentParts = clean(current).split('.').map(int.parse).toList();
      final targetParts = clean(target).split('.').map(int.parse).toList();

      for (var i = 0; i < _semverPartsToCompare; i++) {
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

enum UpdateStatus { upToDate, advisory, required }
