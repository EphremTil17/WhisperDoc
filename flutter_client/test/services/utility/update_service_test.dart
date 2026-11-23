// ignore_for_file: prefer-match-file-name
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/utility/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

class _MockWebSocketService extends Mock implements WebSocketService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PackageInfo.setMockInitialValues(
    appName: 'WhisperDoc',
    packageName: 'whisperdoc',
    version: '3.1.0',
    buildNumber: '1',
    buildSignature: '',
  );
  group('UpdateService.isTrustedReleaseUrl', () {
    test('accepts official GitHub release and asset HTTPS URLs', () {
      expect(UpdateService.isTrustedReleaseUrl(AppConstants.updateUrl), isTrue);
      expect(
        UpdateService.isTrustedReleaseUrl(
          'https://github.com/EphremTil17/WhisperDoc/releases/download/v3.1.0/WhisperDoc_Setup.exe',
        ),
        isTrue,
      );
    });

    test('rejects non-HTTPS, untrusted hosts, wrong repos and userinfo tricks', () {
      const untrusted = [
        'http://github.com/EphremTil17/WhisperDoc/releases/latest',
        'file:///C:/Windows/System32/calc.exe',
        'javascript:alert(1)',
        'https://evil.example/WhisperDoc_Setup.exe',
        'https://github.com/attacker/WhisperDoc/releases/download/v9/evil.exe',
        'https://github.com@evil.example/EphremTil17/WhisperDoc/releases/latest',
        'https://github.com:8443/EphremTil17/WhisperDoc/releases/latest',
        'https://github.com/EphremTil17/WhisperDocX/releases/latest',
        'https://objects.githubusercontent.com/github-production-release-asset/123',
        '',
      ];
      for (final url in untrusted) {
        expect(
          UpdateService.isTrustedReleaseUrl(url),
          isFalse,
          reason: 'should reject $url',
        );
      }
    });
  });

  group('UpdateService lifecycle', () {
    test('dispose detaches its WebSocketService listener', () {
      final ws = _MockWebSocketService();
      when(() => ws.addListener(any())).thenReturn(null);
      when(() => ws.removeListener(any())).thenReturn(null);
      when(() => ws.lastHandshakeError).thenReturn(null);
      when(() => ws.backendMinVersion).thenReturn(null);
      when(() => ws.backendSecVersion).thenReturn(null);
      when(() => ws.backendServerVersion).thenReturn(null);

      final service = UpdateService(ws);
      service.dispose();

      final removed = verify(() => ws.removeListener(any()));
      expect(removed.callCount, 1);
    });
  });

  group('UpdateService version checks', () {
    const installerUrl =
        'https://github.com/EphremTil17/WhisperDoc/releases/download/v3.2.0/WhisperDoc_Setup_v3.2.0.exe';
    const httpOk = 200;
    const httpServerError = 500;
    const runawayRequests = 10;

    final requests = <Uri>[];
    VoidCallback? onServerChange;
    var ws = _MockWebSocketService();

    /// Server-side version hints as the handshake reports them.
    void serverReports({String? min, String? sec, String? server}) {
      when(() => ws.backendMinVersion).thenReturn(min);
      when(() => ws.backendSecVersion).thenReturn(sec);
      when(() => ws.backendServerVersion).thenReturn(server);
    }

    /// A GitHub "latest release" answer naming [tag] and its assets.
    MockClient github(
      String tag, {
      List<Map<String, Object?>> assets = const [
        {'name': 'WhisperDoc_Setup.EXE', 'browser_download_url': installerUrl},
      ],
      int status = httpOk,
    }) => MockClient((request) async {
      requests.add(request.url);
      // A check that re-queries GitHub on every answer loops in microtasks
      // and starves timers, so a timeout could never fire. Stop answering
      // instead, and let the request count fail the test.
      if (requests.length > runawayRequests) {
        return http.Response('', httpServerError);
      }

      return http.Response(
        jsonEncode({'tag_name': tag, 'assets': assets}),
        status,
      );
    });

    /// Starts the service against [client] and lets its checks settle.
    Future<UpdateService> start(MockClient client) async {
      final service = http.runWithClient(() => UpdateService(ws), () => client);
      addTearDown(service.dispose);
      await pumpEventQueue();

      return service;
    }

    setUp(() {
      requests.clear();
      onServerChange = null;
      ws = _MockWebSocketService();
      when(() => ws.addListener(any())).thenAnswer((invocation) {
        onServerChange = invocation.positionalArguments.single as VoidCallback;
      });
      when(() => ws.removeListener(any())).thenReturn(null);
      when(() => ws.lastHandshakeError).thenReturn(null);
      serverReports();
    });

    test('a newer GitHub release offers its installer', () async {
      final service = await start(
        github(
          'v3.2.0',
          assets: [
            {
              'name': 'WhisperDoc_Setup_v3.2.0.zip',
              'browser_download_url': 'https://github.com/EphremTil17/WhisperDoc/releases/download/v3.2.0/WhisperDoc.zip',
            },
            {
              'name': 'WhisperDoc_Setup.EXE',
              'browser_download_url': installerUrl,
            },
          ],
        ),
      );

      expect(requests, [Uri.parse(AppConstants.githubApiLatestRelease)]);
      expect(service.latestVersion, '3.2.0');
      expect(service.latestDownloadUrl, installerUrl);
      expect(service.status, UpdateStatus.advisory);
    });

    test('an installer outside the app repository is never offered', () async {
      final service = await start(
        github(
          'v3.2.0',
          assets: [
            {
              'name': 'WhisperDoc_Setup.exe',
              'browser_download_url':
                  'https://evil.example/WhisperDoc_Setup.exe',
            },
          ],
        ),
      );

      expect(service.latestVersion, '3.2.0');
      expect(service.latestDownloadUrl, isNull);
    });

    test('a release without an installer offers no download', () async {
      final service = await start(
        github(
          'v3.2.0',
          assets: [
            {'name': 'notes.txt', 'browser_download_url': installerUrl},
          ],
        ),
      );

      expect(service.latestDownloadUrl, isNull);
      expect(service.status, UpdateStatus.advisory);
    });

    for (final tag in ['v3.1.0', 'v3.0.9', 'v2.9.9']) {
      test('release $tag is not newer than 3.1.0', () async {
        final service = await start(github(tag));

        expect(service.status, UpdateStatus.upToDate);
      });
    }

    test('a failed GitHub request changes nothing', () async {
      final service = await start(github('v9.0.0', status: httpServerError));

      expect(service.latestVersion, isNull);
      expect(service.latestDownloadUrl, isNull);
      expect(service.status, UpdateStatus.upToDate);
    });

    test('a server minimum above this build requires an update', () async {
      serverReports(min: '3.2.0');

      final service = await start(github('v3.1.0'));

      expect(service.status, UpdateStatus.required);
    });

    test('a server minimum equal to this build is satisfied', () async {
      serverReports(min: '3.1.0', sec: '3.1.0', server: '3.1.0');

      final service = await start(github('v3.1.0'));

      expect(service.status, UpdateStatus.upToDate);
    });

    test('a security version above this build advises an update', () async {
      serverReports(min: '3.0.0', sec: '3.1.1');

      final service = await start(github('v3.1.0'));

      expect(service.status, UpdateStatus.advisory);
    });

    test('a newer server version advises an update', () async {
      serverReports(server: '3.10.0');

      final service = await start(github('v3.1.0'));

      expect(service.status, UpdateStatus.advisory);
    });

    test('build and pre-release suffixes are ignored', () async {
      serverReports(min: '3.1.0+7', server: '3.1.1-beta.2');

      final service = await start(github('v3.1.0'));

      expect(service.status, UpdateStatus.advisory);
    });

    for (final (min, expected) in [
      ('3.1', UpdateStatus.upToDate),
      ('3.2', UpdateStatus.required),
    ]) {
      test('a short minimum $min compares as $min.0', () async {
        serverReports(min: min);

        final service = await start(github('v3.1.0'));

        expect(service.status, expected);
      });
    }

    test('a malformed version never blocks the app', () async {
      serverReports(min: 'latest', sec: '3.x.0');

      final service = await start(github('v3.1.0'));

      expect(service.status, UpdateStatus.upToDate);
    });

    test('an "update required" handshake error requires an update', () async {
      final service = await start(github('v3.1.0'));
      var notified = 0;
      service.addListener(() => notified++);

      when(() => ws.lastHandshakeError)
          .thenReturn('Client Update Required: 3.2.0');
      onServerChange?.call();

      expect(service.status, UpdateStatus.required);
      expect(notified, 1);
    });

    test(
      'new server versions are rechecked without asking GitHub again',
      () async {
        final service = await start(github('v3.1.0'));
        expect(service.status, UpdateStatus.upToDate);

        serverReports(server: '3.2.0');
        onServerChange?.call();
        await pumpEventQueue();

        expect(service.status, UpdateStatus.advisory);
        // GitHub was asked at startup; the 6-hour cooldown holds it off now.
        expect(requests, hasLength(1));
      },
    );

    test('setStatus notifies only on a change', () async {
      final service = await start(github('v3.1.0'));
      var notified = 0;
      service.addListener(() => notified++);

      service.setStatus(UpdateStatus.upToDate);
      service.setStatus(UpdateStatus.advisory);
      service.setStatus(UpdateStatus.advisory);

      expect(service.status, UpdateStatus.advisory);
      expect(notified, 1);
    });
  });
}
