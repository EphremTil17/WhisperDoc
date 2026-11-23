// ignore_for_file: prefer-match-file-name, avoid-late-keyword
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_client/services/utility/secure_vault_service.dart';

class _MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

class _MockDeviceInfoPlugin extends Mock implements DeviceInfoPlugin {}

class _MockWindowsDeviceInfo extends Mock implements WindowsDeviceInfo {}

void main() {
  late SecureVaultService vault;
  late _MockFlutterSecureStorage mockStorage;
  late _MockDeviceInfoPlugin mockDeviceInfo;
  late _MockWindowsDeviceInfo mockWindowsInfo;

  setUpAll(() {
    registerFallbackValue(const WindowsOptions());
  });

  setUp(() {
    mockStorage = _MockFlutterSecureStorage();
    mockDeviceInfo = _MockDeviceInfoPlugin();
    mockWindowsInfo = _MockWindowsDeviceInfo();

    // Setup default mock behavior
    when(() => mockDeviceInfo.windowsInfo)
        .thenAnswer((_) => Future.value(mockWindowsInfo));
    when(() => mockWindowsInfo.deviceId).thenReturn('{uuid-1234}');

    // Default: no salt stored
    when(() => mockStorage.read(key: any(named: 'key')))
        .thenAnswer((_) => Future.value(null));
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

      final writeCall = verify(
        () => mockStorage.write(key: 'api_key', value: 'test-key-123'),
      );
      expect(writeCall.callCount, equals(1));
    });

    test('retrieveCredential returns value from secure storage', () async {
      when(() => mockStorage.read(key: any(named: 'key'))).thenAnswer(
        (_) => Future.value('c29tZS1zYWx0LWJhc2U2NA=='),
      ); // valid base64

      await vault.initialize();

      when(() => mockStorage.read(key: 'api_key'))
          .thenAnswer((_) => Future.value('test-key-123'));

      final result = await vault.retrieveCredential('api_key');

      expect(result, equals('test-key-123'));
    });
  });

  group('SecureVaultService - persistence and fallbacks', () {
    const salt = 'c29tZS1zYWx0LWJhc2U2NA==';
    const saltKey = 'whisperdoc_salt';
    const fallbackIdKey = 'whisperdoc_fallback_device_id';
    const keyBytes = 32;
    final stored = <String, String>{};

    SecureVaultService newVault() =>
        SecureVaultService(storage: mockStorage, deviceInfo: mockDeviceInfo);

    setUp(() {
      stored.clear();
      String keyOf(Invocation call) => call.namedArguments[#key] as String;
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((call) async => stored[keyOf(call)]);
      when(
        () => mockStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((call) async {
        stored[keyOf(call)] = call.namedArguments[#value] as String;
      });
      when(() => mockStorage.delete(key: any(named: 'key')))
          .thenAnswer((call) async => stored.remove(keyOf(call)));
    });

    test('derives the PBKDF2-HMAC-SHA256 key of the device and salt', () async {
      stored[saltKey] = salt;

      await vault.initialize();

      // Python: hashlib.pbkdf2_hmac('sha256', b'{uuid-1234}', salt, 100000, 32)
      expect(
        vault.getEncryptionKey(),
        'OP7K/NyfYHUshdUErxhHkzMNRYvWr19vM0ysbzRO3ZY=',
      );
    });

    test('key bytes are the 256-bit key itself', () async {
      await vault.initialize();

      final bytes = vault.getEncryptionKeyBytes();

      expect(bytes, hasLength(keyBytes));
      expect(base64Encode(bytes), vault.getEncryptionKey());
    });

    test('the salt is created once and reused on later launches', () async {
      await vault.initialize();
      final firstSalt = stored[saltKey];

      final relaunched = newVault();
      await relaunched.initialize();

      expect(base64Decode(firstSalt ?? ''), hasLength(keyBytes));
      expect(stored[saltKey], firstSalt);
      expect(relaunched.getEncryptionKey(), vault.getEncryptionKey());
    });

    test('a blank device ID falls back to a persisted install ID', () async {
      when(() => mockWindowsInfo.deviceId).thenReturn('   ');
      await vault.initialize();
      final installId = stored[fallbackIdKey];

      final relaunched = newVault();
      await relaunched.initialize();

      expect(installId, isNotNull);
      expect(stored[fallbackIdKey], installId);
      expect(relaunched.getEncryptionKey(), vault.getEncryptionKey());
    });

    test('an unreadable device ID falls back to the install ID', () async {
      stored[fallbackIdKey] = 'install-id-1';
      when(() => mockDeviceInfo.windowsInfo)
          .thenThrow(UnsupportedError('no WMI'));
      await vault.initialize();

      when(() => mockDeviceInfo.windowsInfo)
          .thenAnswer((_) async => mockWindowsInfo);
      when(() => mockWindowsInfo.deviceId).thenReturn('install-id-1');
      final sameSecret = newVault();
      await sameSecret.initialize();

      expect(sameSecret.getEncryptionKey(), vault.getEncryptionKey());
    });

    test('credentials are stored, read back and deleted', () async {
      await vault.initialize();

      await vault.storeCredential('groq_api_key', 'gsk_live');
      final read = await vault.retrieveCredential('groq_api_key');
      await vault.deleteCredential('groq_api_key');

      expect(read, 'gsk_live');
      expect(await vault.retrieveCredential('groq_api_key'), isNull);
      expect(stored.containsKey('groq_api_key'), isFalse);
    });

    test('nothing works before initialize', () {
      expect(() => vault.storeCredential('k', 'v'), throwsException);
      expect(() => vault.retrieveCredential('k'), throwsException);
      expect(() => vault.deleteCredential('k'), throwsException);
      expect(vault.getEncryptionKey, throwsException);
      expect(vault.getEncryptionKeyBytes, throwsException);
    });

    test('a failed read is treated as no credential', () async {
      await vault.initialize();
      when(() => mockStorage.read(key: 'api_key'))
          .thenThrow(const FileSystemException('locked'));

      expect(await vault.retrieveCredential('api_key'), isNull);
    });

    test('failed writes and deletes are reported to the caller', () async {
      await vault.initialize();
      when(() => mockStorage.write(key: 'api_key', value: 'v'))
          .thenThrow(const FileSystemException('locked'));
      when(() => mockStorage.delete(key: 'api_key'))
          .thenThrow(const FileSystemException('locked'));

      final reported = throwsA(isA<FileSystemException>());
      await expectLater(vault.storeCredential('api_key', 'v'), reported);
      await expectLater(vault.deleteCredential('api_key'), reported);
    });

    test('a storage failure during initialize leaves it unusable', () async {
      when(() => mockStorage.read(key: saltKey))
          .thenThrow(const FileSystemException('locked'));

      await expectLater(
        vault.initialize(),
        throwsA(isA<FileSystemException>()),
      );
      expect(() => vault.retrieveCredential('api_key'), throwsException);
    });
  });
}
