// ignore_for_file: prefer-match-file-name
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/services/transport/websocket_service.dart';
import 'package:flutter_client/services/utility/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
