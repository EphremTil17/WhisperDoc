// ignore_for_file: avoid-late-keyword
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/services/transport/transport_security_service.dart';

void main() {
  late TransportSecurityService service;

  setUp(() {
    service = TransportSecurityService();
  });

  group('TransportSecurityService - URI Validation', () {
    test('WSS is always allowed for any host', () async {
      final status1 = await service.validateServerUri(
        'wss://whisperdoc.com/ws',
      );
      final status2 = await service.validateServerUri('wss://1.1.1.1/ws');
      final status3 = await service.validateServerUri(
        'wss://localhost:9989/ws',
      );

      final secureStatus = equals(SecurityStatus.secure);
      expect(status1, secureStatus);
      expect(status2, secureStatus);
      expect(status3, secureStatus);
    });

    test('WS is allowed for localhost/loopback', () async {
      final localhostStatus = await service.validateServerUri(
        'ws://localhost:9989/ws',
      );
      final loopbackStatus = await service.validateServerUri(
        'ws://127.0.0.1:9989/ws',
      );

      final localDevStatus = equals(SecurityStatus.localDev);
      expect(localhostStatus, localDevStatus);
      expect(loopbackStatus, localDevStatus);
    });

    test('WS is allowed for RFC 1918 private IPs', () async {
      final class192Status = await service.validateServerUri(
        'ws://192.168.1.100:9989/ws',
      );
      final class10Status = await service.validateServerUri(
        'ws://10.0.0.5:9989/ws',
      );
      final class172Status = await service.validateServerUri(
        'ws://172.16.0.1:9989/ws',
      );

      final localDevStatus = equals(SecurityStatus.localDev);
      expect(class192Status, localDevStatus);
      expect(class10Status, localDevStatus);
      expect(class172Status, localDevStatus);
    });

    test('WS is BLOCKED for public IPs', () async {
      // Simulate/Check public IP (not in private ranges)
      final publicIpStatus = await service.validateServerUri(
        'ws://8.8.8.8:9989/ws',
      );
      final publicHostStatus = await service.validateServerUri(
        'ws://whisperdoc.com/ws',
      );

      final blockedStatus = equals(SecurityStatus.blocked);
      expect(publicIpStatus, blockedStatus);
      expect(publicHostStatus, blockedStatus);
    });

    test('Custom whitelist allows WS', () async {
      // whisper-host.local is whitelisted in constructor
      final whitelistStatus = await service.validateServerUri(
        'ws://whisper-host.local:9989/ws',
      );
      expect(whitelistStatus, equals(SecurityStatus.localDev));
    });
  });
}
