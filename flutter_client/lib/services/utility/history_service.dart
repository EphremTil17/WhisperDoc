import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_client/logic/models/transcription_entry.dart';
import 'package:flutter_client/services/utility/secure_vault_service.dart';
import 'package:flutter_client/services/utility/logging_service.dart';

class HistoryService {
  late Isar _isar;
  final SecureVaultService _vault;
  final LoggingService _logger = LoggingService();
  bool _isInitialized = false;

  late encrypt.Encrypter _encrypter;

  HistoryService(this._vault);

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final dir = await getApplicationSupportDirectory();

      // Get encryption key bytes from vault
      final keyBytes = _vault.getEncryptionKeyBytes();
      final key = encrypt.Key(keyBytes);
      _encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );

      // Isar 3.x on Windows doesn't support native encryptionKey in open()
      // so we use field-level encryption for the transcription content.
      _isar = await Isar.open(
        [TranscriptionEntrySchema],
        directory: dir.path,
        name: 'WhisperDocHistory',
        inspector: true,
      );

      _isInitialized = true;
      _logger.info(
        'HistoryService (Isar) initialized with field-level encryption',
      );
    } catch (e) {
      _logger.error('Failed to initialize HistoryService', error: e);
      rethrow;
    }
  }

  /// Encrypt and save a transcription
  Future<void> saveTranscription({
    required String text,
    required DateTime timestamp,
    int? durationMs,
    bool isIncognito = false,
  }) async {
    _ensureInitialized();
    if (isIncognito) return;

    final iv = encrypt.IV.fromLength(16);
    final encrypted = _encrypter.encrypt(text, iv: iv);

    final entry = TranscriptionEntry(
      encryptedText: encrypted.base64,
      ivBase64: iv.base64,
      timestamp: timestamp,
      durationMs: durationMs,
      isIncognito: isIncognito,
    );

    await _isar.writeTxn(() async {
      await _isar.transcriptionEntrys.put(entry);
    });
  }

  /// Decrypt a transcription entry
  String decryptEntry(TranscriptionEntry entry) {
    _ensureInitialized();
    final iv = encrypt.IV.fromBase64(entry.ivBase64);
    final encrypted = encrypt.Encrypted.fromBase64(entry.encryptedText);
    return _encrypter.decrypt(encrypted, iv: iv);
  }

  Future<List<TranscriptionEntry>> getHistory({int limit = 50}) async {
    _ensureInitialized();
    return await _isar.transcriptionEntrys
        .where()
        .sortByTimestampDesc()
        .limit(limit)
        .findAll();
  }

  Future<void> clearAll() async {
    _ensureInitialized();
    await _isar.writeTxn(() async {
      await _isar.transcriptionEntrys.clear();
    });
    _logger.warning('Transcription history cleared');
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw Exception(
        'HistoryService not initialized. Call initialize() first.',
      );
    }
  }

  Future<void> dispose() async {
    if (_isInitialized) {
      await _isar.close();
    }
  }
}
