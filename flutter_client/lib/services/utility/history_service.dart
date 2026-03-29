import 'dart:io';

import 'package:drift/drift.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:flutter_client/infrastructure/database/app_database.dart'
    hide TranscriptionEntry;
import 'package:flutter_client/logic/models/transcription_entry.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/services/utility/secure_vault_service.dart';

class HistoryService {
  static const String _gcmPrefix = 'gcm:';

  late AppDatabase _db;
  final SecureVaultService _vault;
  final LoggingService _logger = LoggingService();
  bool _isInitialized = false;

  late encrypt.Encrypter _gcmEncrypter;
  late encrypt.Encrypter _legacyCbcEncrypter;

  HistoryService(this._vault);

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final keyBytes = _vault.getEncryptionKeyBytes();
      final key = encrypt.Key(keyBytes);
      _gcmEncrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.gcm),
      );
      _legacyCbcEncrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc),
      );

      _db = await AppDatabase.open();

      _isInitialized = true;
      _logger.info(
        'HistoryService (Drift/SQLite) initialized with field-level encryption',
      );

      // One-time cleanup: remove old Isar database files if present.
      await _cleanupLegacyIsarFiles();
    } catch (e) {
      _logger.error('Failed to initialize HistoryService', error: e);
      rethrow;
    }
  }

  /// Encrypt and save a transcription.
  Future<void> saveTranscription({
    required String text,
    required DateTime timestamp,
    int? durationMs,
    bool isIncognito = false,
  }) async {
    _ensureInitialized();
    if (isIncognito) return;

    // AES-GCM is most efficient and conventional with a 96-bit (12-byte) nonce.
    final iv = encrypt.IV.fromSecureRandom(12);
    final encrypted = _gcmEncrypter.encrypt(text, iv: iv);

    await _db.into(_db.transcriptionEntries).insert(
          TranscriptionEntriesCompanion.insert(
            encryptedText: '$_gcmPrefix${encrypted.base64}',
            ivBase64: iv.base64,
            timestamp: timestamp,
            durationMs: Value(durationMs),
            isIncognito: Value(isIncognito),
          ),
        );
  }

  /// Decrypt a transcription entry.
  String decryptEntry(TranscriptionEntry entry) {
    _ensureInitialized();
    final iv = encrypt.IV.fromBase64(entry.ivBase64);

    if (entry.encryptedText.startsWith(_gcmPrefix)) {
      final encrypted = encrypt.Encrypted.fromBase64(
        entry.encryptedText.substring(_gcmPrefix.length),
      );
      return _gcmEncrypter.decrypt(encrypted, iv: iv);
    }

    // Backward-compatibility for pre-hardening history entries written with
    // AES-CBC. New entries are always written as AES-GCM.
    final encrypted = encrypt.Encrypted.fromBase64(entry.encryptedText);
    return _legacyCbcEncrypter.decrypt(encrypted, iv: iv);
  }

  Future<List<TranscriptionEntry>> getHistory({int limit = 50}) async {
    _ensureInitialized();
    final rows = await (_db.select(_db.transcriptionEntries)
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
          ..limit(limit))
        .get();

    return rows
        .map(
          (row) => TranscriptionEntry(
            id: row.id,
            encryptedText: row.encryptedText,
            ivBase64: row.ivBase64,
            timestamp: row.timestamp,
            durationMs: row.durationMs,
            isIncognito: row.isIncognito,
          ),
        )
        .toList();
  }

  Future<void> clearAll() async {
    _ensureInitialized();
    await _db.delete(_db.transcriptionEntries).go();
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
      await _db.close();
    }
  }

  /// Remove legacy Isar database files from the app support directory.
  Future<void> _cleanupLegacyIsarFiles() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final isarFile = File(p.join(dir.path, 'WhisperDocHistory.isar'));
      if (isarFile.existsSync()) {
        isarFile.deleteSync();
        final lockFile = File(p.join(dir.path, 'WhisperDocHistory.isar.lock'));
        if (lockFile.existsSync()) lockFile.deleteSync();
        _logger.info('Cleaned up legacy Isar database files');
      }
    } catch (e) {
      _logger.warning('Failed to clean up legacy Isar files: $e');
    }
  }
}
