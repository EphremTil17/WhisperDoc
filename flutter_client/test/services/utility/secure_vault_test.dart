import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_client/services/utility/secure_vault_service.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class MockDeviceInfoPlugin extends Mock implements DeviceInfoPlugin {}

class MockWindowsDeviceInfo extends Mock implements WindowsDeviceInfo {}

void main() {
  late SecureVaultService vault;
  late MockFlutterSecureStorage mockStorage;
  late MockDeviceInfoPlugin mockDeviceInfo;
  late MockWindowsDeviceInfo mockWindowsInfo;

  setUpAll(() {
    registerFallbackValue(const WindowsOptions());
  });

  setUp(() {
    mockStorage = MockFlutterSecureStorage();
    mockDeviceInfo = MockDeviceInfoPlugin();
    mockWindowsInfo = MockWindowsDeviceInfo();

    // Setup default mock behavior
    when(
      () => mockDeviceInfo.windowsInfo,
    ).thenAnswer((_) => Future.value(mockWindowsInfo));
    when(() => mockWindowsInfo.deviceId).thenReturn('{uuid-1234}');

    // Default: no salt stored
    when(
      () => mockStorage.read(key: any(named: 'key')),
    ).thenAnswer((_) => Future.value(null));
    when(
      () => mockStorage.write(
        key: any(named: 'key'),
        value: any(named: 'value'),
      ),
    ).thenAnswer((_) => Future.value());

    vault = SecureVaultService(
      storage: mockStorage,
      deviceInfo: mockDeviceInfo,
    );
  });

  group('SecureVaultService - Key Derivation', () {
    test(
      'deriveEncryptionKey produces consistent key from device ID',
      () async {
        await vault.initialize();
        final key1 = vault.getEncryptionKey();
        final key2 = vault.getEncryptionKey();

        expect(key1, isNotEmpty);
        expect(key1, equals(key2));
      },
    );

    test(
      'deriveEncryptionKey changes if hardware ID changes (simulated)',
      () async {
        await vault.initialize();
        final key1 = vault.getEncryptionKey();

        // Change hardware ID
        when(() => mockWindowsInfo.deviceId).thenReturn('{uuid-5678}');

        // We need to create a new vault instance to pick up the change
        final newVault = SecureVaultService(
          storage: mockStorage,
          deviceInfo: mockDeviceInfo,
        );

        await newVault.initialize();
        final key2 = newVault.getEncryptionKey();

        expect(key1, isNot(equals(key2)));
      },
    );
  });

  group('SecureVaultService - Storage Operations', () {
    test('storeCredential calls secure storage', () async {
      when(() => mockStorage.read(key: any(named: 'key'))).thenAnswer(
        (_) => Future.value('c29tZS1zYWx0LWJhc2U2NA=='),
      ); // valid base64

      await vault.initialize();

      when(
        () => mockStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) => Future.value());

      await vault.storeCredential('api_key', 'test-key-123');

      verify(
        () => mockStorage.write(key: 'api_key', value: 'test-key-123'),
      ).called(1);
    });

    test('retrieveCredential returns value from secure storage', () async {
      when(() => mockStorage.read(key: any(named: 'key'))).thenAnswer(
        (_) => Future.value('c29tZS1zYWx0LWJhc2U2NA=='),
      ); // valid base64

      await vault.initialize();

      when(
        () => mockStorage.read(key: 'api_key'),
      ).thenAnswer((_) => Future.value('test-key-123'));

      final result = await vault.retrieveCredential('api_key');

      expect(result, equals('test-key-123'));
    });
  });
}
