import 'package:drift/drift.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

import 'package:flutter_client/infrastructure/database/app_database.dart';
import 'package:flutter_client/logic/models/history_entry.dart';
import 'package:flutter_client/services/utility/logging_service.dart';
import 'package:flutter_client/services/utility/secure_vault_service.dart';

class HistoryService {
  static const String _gcmPrefix = 'gcm:';
  static const int _gcmNonceBytes = 12;
  static const int _defaultHistoryLimit = 50;

  final SecureVaultService _vault;
  final LoggingService _logger = LoggingService();

  AppDatabase? _db;
  encrypt.Encrypter? _gcmEncrypter;
  bool _isInitialized = false;

  HistoryService(this._vault);

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final keyBytes = _vault.getEncryptionKeyBytes();
      final key = encrypt.Key(keyBytes);
      _gcmEncrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.gcm),
      );

      _db = await AppDatabase.open();

      _isInitialized = true;
      _logger.info(
        'HistoryService (Drift/SQLite) initialized with field-level encryption',
      );
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
    final db = _requireDb();
    final encrypter = _requireEncrypter();
    if (isIncognito) return;

    // AES-GCM is most efficient and conventional with a 96-bit (12-byte) nonce.
    final iv = encrypt.IV.fromSecureRandom(_gcmNonceBytes);
    final encrypted = encrypter.encrypt(text, iv: iv);
    final transcriptionEntries = db.transcriptionEntries;

    await db
        .into(transcriptionEntries)
        .insert(
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
  String decryptEntry(HistoryEntry entry) {
    final encrypter = _requireEncrypter();
    final iv = encrypt.IV.fromBase64(entry.ivBase64);
    final encrypted = encrypt.Encrypted.fromBase64(
      entry.encryptedText.replaceFirst(_gcmPrefix, ''),
    );

    return encrypter.decrypt(encrypted, iv: iv);
  }

  Future<List<HistoryEntry>> getHistory({
    int limit = _defaultHistoryLimit,
  }) async {
    final db = _requireDb();
    final transcriptionEntries = db.transcriptionEntries;
    final rows =
        await (db.select(transcriptionEntries)
              ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
              ..limit(limit))
            .get();

    return rows
        .map(
          (row) => HistoryEntry(
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
    final db = _requireDb();
    final transcriptionEntries = db.transcriptionEntries;
    await db.delete(transcriptionEntries).go();
    _logger.warning('Transcription history cleared');
  }

  Future<void> dispose() async {
    if (_isInitialized) {
      await _db?.close();
    }
  }

  AppDatabase _requireDb() {
    final db = _db;
    if (!_isInitialized || db == null) {
      throw StateError(
        'HistoryService not initialized. Call initialize() first.',
      );
    }

    return db;
  }

  encrypt.Encrypter _requireEncrypter() {
    final encrypter = _gcmEncrypter;
    if (!_isInitialized || encrypter == null) {
      throw StateError(
        'HistoryService not initialized. Call initialize() first.',
      );
    }

    return encrypter;
  }
}
