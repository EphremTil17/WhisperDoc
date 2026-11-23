// ignore_for_file: prefer-match-file-name, avoid-late-keyword
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_client/infrastructure/constants/app_constants.dart';
import 'package:flutter_client/infrastructure/database/app_database.dart';
import 'package:flutter_client/logic/models/history_entry.dart';
import 'package:flutter_client/services/utility/history_service.dart';
import 'package:flutter_client/services/utility/secure_vault_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSecureVaultService extends Mock implements SecureVaultService {}

void main() {
  const keyLength = 32;
  const otherKeyFill = 7;

  late AppDatabase db;
  late _MockSecureVaultService vault;
  late HistoryService history;

  /// A history service over the shared in-memory [db], encrypting with a key
  /// of [keyLength] bytes all equal to [fill].
  Future<HistoryService> openHistory({int fill = 1}) async {
    final keyVault = _MockSecureVaultService();
    when(keyVault.getEncryptionKeyBytes)
        .thenReturn(Uint8List.fromList(List.filled(keyLength, fill)));
    final service = HistoryService(keyVault, openDatabase: () async => db);
    await service.initialize();

    return service;
  }

  /// Every row as stored on disk.
  Future<List<TranscriptionEntry>> storedRows() {
    final table = db.transcriptionEntries;

    return db.select(table).get();
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    vault = _MockSecureVaultService();
    when(vault.getEncryptionKeyBytes)
        .thenReturn(Uint8List.fromList(List.filled(keyLength, 1)));
    history = HistoryService(vault, openDatabase: () async => db);
    await history.initialize();
  });

  tearDown(() => db.close());

  group('HistoryService', () {
    test('a saved transcript reads back as the same text', () async {
      final at = DateTime(2026, 11, 22, 9, 30);
      await history.saveTranscription(text: 'Dear Dr. Abebe, ✓', timestamp: at);

      final entries = await history.getHistory();

      expect(entries, hasLength(1));
      expect(entries.single.timestamp, at);
      expect(entries.single.isIncognito, isFalse);
      expect(history.decryptEntry(entries.single), 'Dear Dr. Abebe, ✓');
    });

    test('stores only ciphertext, tagged as AES-GCM', () async {
      const secret = 'patient name: Jane Doe';
      await history.saveTranscription(text: secret, timestamp: DateTime(2026));

      final row = (await storedRows()).single;

      expect(row.encryptedText, startsWith('gcm:'));
      expect(row.encryptedText, isNot(contains('Jane')));
      expect(row.ivBase64, isNotEmpty);
    });

    test(
      'each save uses a fresh nonce, so equal text differs on disk',
      () async {
        await history.saveTranscription(
          text: 'same',
          timestamp: DateTime(2026),
        );
        await history.saveTranscription(
          text: 'same',
          timestamp: DateTime(2027),
        );

        final rows = await storedRows();

        expect(rows.first.ivBase64, isNot(rows.last.ivBase64));
        expect(rows.first.encryptedText, isNot(rows.last.encryptedText));
      },
    );

    test('a different key cannot read the history', () async {
      await history.saveTranscription(
        text: 'private',
        timestamp: DateTime(2026),
      );
      final other = await openHistory(fill: otherKeyFill);

      final entry = (await other.getHistory()).single;

      expect(() => other.decryptEntry(entry), throwsA(anything));
    });

    test('a tampered entry fails authentication', () async {
      await history.saveTranscription(
        text: 'original',
        timestamp: DateTime(2026),
      );
      final entry = (await history.getHistory()).single;
      final tampered = HistoryEntry(
        encryptedText: entry.encryptedText.replaceRange(
          'gcm:'.length,
          'gcm:'.length + 1,
          entry.encryptedText['gcm:'.length] == 'A' ? 'B' : 'A',
        ),
        ivBase64: entry.ivBase64,
        timestamp: entry.timestamp,
      );

      expect(() => history.decryptEntry(tampered), throwsA(anything));
    });

    test('lists newest first and honours the limit', () async {
      final base = DateTime(2026, 11, 1);
      for (final day in [3, 1, 2]) {
        await history.saveTranscription(
          text: 'day $day',
          timestamp: base.add(Duration(days: day)),
        );
      }

      final all = await history.getHistory();
      final newest = await history.getHistory(limit: 1);

      expect(all.map(history.decryptEntry), ['day 3', 'day 2', 'day 1']);
      expect(newest.map(history.decryptEntry), ['day 3']);
    });

    test('keeps only the newest maxHistorySize transcripts', () async {
      const extra = 2;
      const total = AppConstants.maxHistorySize + extra;
      final base = DateTime(2026);
      for (var i = 0; i < total; i++) {
        await history.saveTranscription(
          text: 'entry $i',
          timestamp: base.add(Duration(minutes: i)),
        );
      }

      final rows = await storedRows();
      final kept = await history.getHistory(limit: total);

      expect(rows, hasLength(AppConstants.maxHistorySize));
      expect(history.decryptEntry(kept.first), 'entry ${total - 1}');
      expect(history.decryptEntry(kept.last), 'entry $extra');
    });

    test('clearAll deletes every transcript', () async {
      await history.saveTranscription(text: 'one', timestamp: DateTime(2026));
      await history.saveTranscription(text: 'two', timestamp: DateTime(2027));

      await history.clearAll();

      expect(await history.getHistory(), isEmpty);
      expect(await storedRows(), isEmpty);
    });

    test('clearAll still succeeds when VACUUM cannot run', () async {
      await history.saveTranscription(text: 'one', timestamp: DateTime(2026));

      // SQLite refuses VACUUM inside a transaction; the rows must still go.
      await db.transaction(() => history.clearAll());

      expect(await history.getHistory(), isEmpty);
    });

    test('initialize is idempotent and opens the database once', () async {
      var opens = 0;
      final counted = HistoryService(
        vault,
        openDatabase: () async {
          opens++;

          return db;
        },
      );

      await counted.initialize();
      await counted.initialize();

      expect(opens, 1);
    });

    test('a failing key read leaves the service unusable', () async {
      final broken = _MockSecureVaultService();
      when(broken.getEncryptionKeyBytes).thenThrow(StateError('vault locked'));
      final service = HistoryService(broken, openDatabase: () async => db);

      await expectLater(service.initialize, throwsStateError);
      expect(service.getHistory, throwsStateError);
    });

    test('every operation needs initialize first', () {
      final fresh = HistoryService(vault, openDatabase: () async => db);
      final entry = HistoryEntry(
        encryptedText: 'gcm:AAAA',
        ivBase64: 'AAAAAAAAAAAAAAAA',
        timestamp: DateTime(2026),
      );

      expect(
        () => fresh.saveTranscription(text: 'x', timestamp: DateTime(2026)),
        throwsStateError,
      );
      expect(() => fresh.decryptEntry(entry), throwsStateError);
      expect(fresh.getHistory, throwsStateError);
      expect(fresh.clearAll, throwsStateError);
    });

    test('dispose closes the database it opened', () async {
      await history.saveTranscription(text: 'one', timestamp: DateTime(2026));

      await history.dispose();

      // Drift refuses to reopen a database once it has been closed.
      await expectLater(storedRows(), throwsStateError);
    });

    test('dispose before initialize leaves the database alone', () async {
      await history.saveTranscription(text: 'one', timestamp: DateTime(2026));
      final unopened = HistoryService(vault, openDatabase: () async => db);

      await unopened.dispose();

      expect(await storedRows(), hasLength(1));
    });
  });
}
