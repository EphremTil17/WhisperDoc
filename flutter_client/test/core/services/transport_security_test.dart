import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_client/core/services/transport_security_service.dart';

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

      expect(status1, equals(SecurityStatus.secure));
      expect(status2, equals(SecurityStatus.secure));
      expect(status3, equals(SecurityStatus.secure));
    });

    test('WS is allowed for localhost/loopback', () async {
      expect(
        await service.validateServerUri('ws://localhost:9989/ws'),
        equals(SecurityStatus.localDev),
      );
      expect(
        await service.validateServerUri('ws://127.0.0.1:9989/ws'),
        equals(SecurityStatus.localDev),
      );
    });

    test('WS is allowed for RFC 1918 private IPs', () async {
      expect(
        await service.validateServerUri('ws://192.168.1.100:9989/ws'),
        equals(SecurityStatus.localDev),
      );
      expect(
        await service.validateServerUri('ws://10.0.0.5:9989/ws'),
        equals(SecurityStatus.localDev),
      );
      expect(
        await service.validateServerUri('ws://172.16.0.1:9989/ws'),
        equals(SecurityStatus.localDev),
      );
    });

    test('WS is BLOCKED for public IPs', () async {
      // Simulate/Check public IP (not in private ranges)
      expect(
        await service.validateServerUri('ws://8.8.8.8:9989/ws'),
        equals(SecurityStatus.blocked),
      );
      expect(
        await service.validateServerUri('ws://whisperdoc.com/ws'),
        equals(SecurityStatus.blocked),
      );
    });

    test('Custom whitelist allows WS', () async {
      // whisper-host.local is whitelisted in constructor
      expect(
        await service.validateServerUri('ws://whisper-host.local:9989/ws'),
        equals(SecurityStatus.localDev),
      );
    });
  });
}
