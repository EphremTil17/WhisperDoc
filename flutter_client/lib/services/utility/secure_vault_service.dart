import 'dart:convert';
import 'dart:math' show Random;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_client/services/utility/logging_service.dart';

/// Secure credential storage using Windows Credential Manager via flutter_secure_storage.
///
/// Implements hardware-bound encryption using PBKDF2 key derivation:
/// - Encryption Key = PBKDF2(device_id + salt, iterations=100000)
/// - Salt is randomly generated once and stored in secure storage
/// - Device ID is fetched from Windows machine ID
///
/// Security Properties:
/// - Even if .sqlite file is stolen, it cannot be decrypted on another machine
/// - Credentials stored in Windows Credential Manager (encrypted at-rest)
/// - No plain-text credentials in SharedPreferences
class SecureVaultService {
  static const String _saltKey = 'whisperdoc_salt';
  static const String _fallbackDeviceIdKey = 'whisperdoc_fallback_device_id';
  static const int _pbkdf2Iterations = 100000;
  static const int _keyLength = 32; // 256-bit key
  static const int _saltByteLength = 32;
  static const int _fallbackIdByteLength = 32;
  static const int _randomByteRange = 256;
  static const int _blockIndexByteSize = 4;

  bool _isInitialized = false;
  String? _encryptionKey;

  final FlutterSecureStorage _storage;
  final DeviceInfoPlugin _deviceInfo;
  final LoggingService _logger = LoggingService();

  SecureVaultService({
    FlutterSecureStorage? storage,
    DeviceInfoPlugin? deviceInfo,
  }) : _storage =
           storage ??
           const FlutterSecureStorage(
             wOptions: WindowsOptions(useBackwardCompatibility: false),
           ),
       _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  /// Initialize the vault service. Must be called before any operations.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. Get or generate salt
      String? salt = await _storage.read(key: _saltKey);
      if (salt == null) {
        salt = _generateSalt();
        await _storage.write(key: _saltKey, value: salt);
        _logger.info('Generated new salt for encryption key derivation');
      }

      // 2. Get device hardware ID
      final deviceId = await _getDeviceId();

      // 3. Derive encryption key using PBKDF2
      _encryptionKey = _deriveKey(deviceId, salt);

      _isInitialized = true;
      _logger.info('SecureVaultService initialized successfully');
    } catch (e) {
      _logger.error('Failed to initialize SecureVaultService', error: e);
      rethrow;
    }
  }

  /// Store a credential in the secure vault
  Future<void> storeCredential(String key, String value) async {
    _ensureInitialized();
    try {
      await _storage.write(key: key, value: value);
      _logger.info('Credential stored in secure vault: $key');
    } catch (e) {
      _logger.error('Failed to store credential: $key', error: e);
      rethrow;
    }
  }

  /// Retrieve a credential from the secure vault
  Future<String?> retrieveCredential(String key) async {
    _ensureInitialized();
    try {
      final value = await _storage.read(key: key);
      if (value != null) {
        _logger.info('Credential retrieved from secure vault: $key');
      }

      return value;
    } catch (e) {
      _logger.error('Failed to retrieve credential: $key', error: e);

      return null;
    }
  }

  /// Delete a credential from the secure vault
  Future<void> deleteCredential(String key) async {
    _ensureInitialized();
    try {
      await _storage.delete(key: key);
      _logger.info('Credential deleted from secure vault: $key');
    } catch (e) {
      _logger.error('Failed to delete credential: $key', error: e);
      rethrow;
    }
  }

  /// Check if a credential exists in the vault
  Future<bool> hasCredential(String key) async {
    _ensureInitialized();
    final value = await _storage.read(key: key);

    return value != null;
  }

  /// Clear all credentials from the vault
  Future<void> clearAll() async {
    _ensureInitialized();
    try {
      await _storage.deleteAll();
      _logger.warning('All credentials cleared from secure vault');
      _isInitialized = false;
    } catch (e) {
      _logger.error('Failed to clear vault', error: e);
      rethrow;
    }
  }

  /// Get the derived encryption key for database encryption
  String getEncryptionKey() {
    _ensureInitialized();
    final encryptionKey = _encryptionKey;
    if (encryptionKey == null) {
      throw StateError('SecureVaultService encryption key is unavailable.');
    }

    return encryptionKey;
  }

  /// Get the derived encryption key as raw bytes for database field-level encryption
  Uint8List getEncryptionKeyBytes() {
    _ensureInitialized();
    final encryptionKey = _encryptionKey;
    if (encryptionKey == null) {
      throw StateError('SecureVaultService encryption key is unavailable.');
    }

    return base64Decode(encryptionKey);
  }

  // --- Private Helper Methods ---

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw Exception(
        'SecureVaultService not initialized. Call initialize() first.',
      );
    }
  }

  Future<String> _getDeviceId() async {
    try {
      final windowsInfo = await _deviceInfo.windowsInfo;
      // Use Windows machine GUID as device ID
      final deviceId = windowsInfo.deviceId.trim();
      if (deviceId.isNotEmpty) {
        return deviceId;
      }
      _logger.warning('Device ID was empty, using persisted fallback');

      return _getOrCreateFallbackDeviceId();
    } catch (e) {
      _logger.warning('Failed to get device ID, using persisted fallback');

      return _getOrCreateFallbackDeviceId();
    }
  }

  String _generateSalt() {
    // Generate 32-byte cryptographically secure random salt
    return _generateRandomBase64(_saltByteLength);
  }

  String _generateRandomBase64(int byteLength) {
    final secureRandom = Random.secure();
    final random = List<int>.generate(
      byteLength,
      (_) => secureRandom.nextInt(_randomByteRange),
    );

    return base64Encode(random);
  }

  Future<String> _getOrCreateFallbackDeviceId() async {
    final existing = await _storage.read(key: _fallbackDeviceIdKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final generated = _generateRandomBase64(_fallbackIdByteLength);
    await _storage.write(key: _fallbackDeviceIdKey, value: generated);
    _logger.warning(
      'Persisted per-install fallback device identifier for key derivation',
    );

    return generated;
  }

  String _deriveKey(String deviceId, String salt) {
    // PBKDF2-HMAC-SHA256 key derivation
    final password = utf8.encode(deviceId);
    final saltBytes = base64Decode(salt);
    final prf = Hmac(sha256, password);
    final hLen = sha256.convert(const <int>[]).bytes.length;
    final blockCount = (_keyLength / hLen).ceil();
    final derivedKey = Uint8List(_keyLength);

    var outputOffset = 0;
    for (var blockIndex = 1; blockIndex <= blockCount; blockIndex++) {
      final block = _pbkdf2Block(
        prf: prf,
        salt: saltBytes,
        blockIndex: blockIndex,
      );
      final remaining = _keyLength - outputOffset;
      final bytesToCopy = remaining < block.length ? remaining : block.length;
      derivedKey.setRange(
        outputOffset,
        outputOffset + bytesToCopy,
        block.take(bytesToCopy),
      );
      outputOffset += bytesToCopy;
    }

    return base64Encode(derivedKey);
  }

  List<int> _pbkdf2Block({
    required Hmac prf,
    required List<int> salt,
    required int blockIndex,
  }) {
    final blockIndexBytes = ByteData(_blockIndexByteSize)
      ..setUint32(0, blockIndex, Endian.big);
    var u = prf.convert([
      ...salt,
      ...blockIndexBytes.buffer.asUint8List(),
    ]).bytes;
    final output = Uint8List.fromList(u);

    for (var i = 1; i < _pbkdf2Iterations; i++) {
      u = prf.convert(u).bytes;
      for (var j = 0; j < output.length; j++) {
        output[j] ^= u[j];
      }
    }

    return output;
  }
}
