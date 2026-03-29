import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [TranscriptionEntries])
class AppDatabase extends _$AppDatabase {
  @override
  int get schemaVersion => 1;

  AppDatabase(super.e);

  /// Opens the database file in the app support directory.
  static Future<AppDatabase> open() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'whisperdoc_history.sqlite'));

    return AppDatabase(NativeDatabase.createInBackground(file));
  }
}

/// Drift table mapping to the transcription_entries SQLite table.
class TranscriptionEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get encryptedText => text()();
  TextColumn get ivBase64 => text()();
  DateTimeColumn get timestamp => dateTime()();
  IntColumn get durationMs => integer().nullable()();
  BoolColumn get isIncognito => boolean().withDefault(const Constant(false))();
}
