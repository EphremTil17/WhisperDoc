// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $TranscriptionEntriesTable extends TranscriptionEntries
    with TableInfo<$TranscriptionEntriesTable, TranscriptionEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TranscriptionEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _encryptedTextMeta = const VerificationMeta(
    'encryptedText',
  );
  @override
  late final GeneratedColumn<String> encryptedText = GeneratedColumn<String>(
    'encrypted_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ivBase64Meta = const VerificationMeta(
    'ivBase64',
  );
  @override
  late final GeneratedColumn<String> ivBase64 = GeneratedColumn<String>(
    'iv_base64',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isIncognitoMeta = const VerificationMeta(
    'isIncognito',
  );
  @override
  late final GeneratedColumn<bool> isIncognito = GeneratedColumn<bool>(
    'is_incognito',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_incognito" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    encryptedText,
    ivBase64,
    timestamp,
    durationMs,
    isIncognito,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transcription_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<TranscriptionEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('encrypted_text')) {
      context.handle(
        _encryptedTextMeta,
        encryptedText.isAcceptableOrUnknown(
          data['encrypted_text']!,
          _encryptedTextMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptedTextMeta);
    }
    if (data.containsKey('iv_base64')) {
      context.handle(
        _ivBase64Meta,
        ivBase64.isAcceptableOrUnknown(data['iv_base64']!, _ivBase64Meta),
      );
    } else if (isInserting) {
      context.missing(_ivBase64Meta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    }
    if (data.containsKey('is_incognito')) {
      context.handle(
        _isIncognitoMeta,
        isIncognito.isAcceptableOrUnknown(
          data['is_incognito']!,
          _isIncognitoMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TranscriptionEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TranscriptionEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      encryptedText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}encrypted_text'],
      )!,
      ivBase64: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}iv_base64'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      ),
      isIncognito: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_incognito'],
      )!,
    );
  }

  @override
  $TranscriptionEntriesTable createAlias(String alias) {
    return $TranscriptionEntriesTable(attachedDatabase, alias);
  }
}

class TranscriptionEntry extends DataClass
    implements Insertable<TranscriptionEntry> {
  final int id;
  final String encryptedText;
  final String ivBase64;
  final DateTime timestamp;
  final int? durationMs;
  final bool isIncognito;
  const TranscriptionEntry({
    required this.id,
    required this.encryptedText,
    required this.ivBase64,
    required this.timestamp,
    this.durationMs,
    required this.isIncognito,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['encrypted_text'] = Variable<String>(encryptedText);
    map['iv_base64'] = Variable<String>(ivBase64);
    map['timestamp'] = Variable<DateTime>(timestamp);
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    map['is_incognito'] = Variable<bool>(isIncognito);
    return map;
  }

  TranscriptionEntriesCompanion toCompanion(bool nullToAbsent) {
    return TranscriptionEntriesCompanion(
      id: Value(id),
      encryptedText: Value(encryptedText),
      ivBase64: Value(ivBase64),
      timestamp: Value(timestamp),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      isIncognito: Value(isIncognito),
    );
  }

  factory TranscriptionEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TranscriptionEntry(
      id: serializer.fromJson<int>(json['id']),
      encryptedText: serializer.fromJson<String>(json['encryptedText']),
      ivBase64: serializer.fromJson<String>(json['ivBase64']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      isIncognito: serializer.fromJson<bool>(json['isIncognito']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'encryptedText': serializer.toJson<String>(encryptedText),
      'ivBase64': serializer.toJson<String>(ivBase64),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'durationMs': serializer.toJson<int?>(durationMs),
      'isIncognito': serializer.toJson<bool>(isIncognito),
    };
  }

  TranscriptionEntry copyWith({
    int? id,
    String? encryptedText,
    String? ivBase64,
    DateTime? timestamp,
    Value<int?> durationMs = const Value.absent(),
    bool? isIncognito,
  }) => TranscriptionEntry(
    id: id ?? this.id,
    encryptedText: encryptedText ?? this.encryptedText,
    ivBase64: ivBase64 ?? this.ivBase64,
    timestamp: timestamp ?? this.timestamp,
    durationMs: durationMs.present ? durationMs.value : this.durationMs,
    isIncognito: isIncognito ?? this.isIncognito,
  );
  TranscriptionEntry copyWithCompanion(TranscriptionEntriesCompanion data) {
    return TranscriptionEntry(
      id: data.id.present ? data.id.value : this.id,
      encryptedText: data.encryptedText.present
          ? data.encryptedText.value
          : this.encryptedText,
      ivBase64: data.ivBase64.present ? data.ivBase64.value : this.ivBase64,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      isIncognito: data.isIncognito.present
          ? data.isIncognito.value
          : this.isIncognito,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TranscriptionEntry(')
          ..write('id: $id, ')
          ..write('encryptedText: $encryptedText, ')
          ..write('ivBase64: $ivBase64, ')
          ..write('timestamp: $timestamp, ')
          ..write('durationMs: $durationMs, ')
          ..write('isIncognito: $isIncognito')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    encryptedText,
    ivBase64,
    timestamp,
    durationMs,
    isIncognito,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TranscriptionEntry &&
          other.id == this.id &&
          other.encryptedText == this.encryptedText &&
          other.ivBase64 == this.ivBase64 &&
          other.timestamp == this.timestamp &&
          other.durationMs == this.durationMs &&
          other.isIncognito == this.isIncognito);
}

class TranscriptionEntriesCompanion
    extends UpdateCompanion<TranscriptionEntry> {
  final Value<int> id;
  final Value<String> encryptedText;
  final Value<String> ivBase64;
  final Value<DateTime> timestamp;
  final Value<int?> durationMs;
  final Value<bool> isIncognito;
  const TranscriptionEntriesCompanion({
    this.id = const Value.absent(),
    this.encryptedText = const Value.absent(),
    this.ivBase64 = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.isIncognito = const Value.absent(),
  });
  TranscriptionEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String encryptedText,
    required String ivBase64,
    required DateTime timestamp,
    this.durationMs = const Value.absent(),
    this.isIncognito = const Value.absent(),
  }) : encryptedText = Value(encryptedText),
       ivBase64 = Value(ivBase64),
       timestamp = Value(timestamp);
  static Insertable<TranscriptionEntry> custom({
    Expression<int>? id,
    Expression<String>? encryptedText,
    Expression<String>? ivBase64,
    Expression<DateTime>? timestamp,
    Expression<int>? durationMs,
    Expression<bool>? isIncognito,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (encryptedText != null) 'encrypted_text': encryptedText,
      if (ivBase64 != null) 'iv_base64': ivBase64,
      if (timestamp != null) 'timestamp': timestamp,
      if (durationMs != null) 'duration_ms': durationMs,
      if (isIncognito != null) 'is_incognito': isIncognito,
    });
  }

  TranscriptionEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? encryptedText,
    Value<String>? ivBase64,
    Value<DateTime>? timestamp,
    Value<int?>? durationMs,
    Value<bool>? isIncognito,
  }) {
    return TranscriptionEntriesCompanion(
      id: id ?? this.id,
      encryptedText: encryptedText ?? this.encryptedText,
      ivBase64: ivBase64 ?? this.ivBase64,
      timestamp: timestamp ?? this.timestamp,
      durationMs: durationMs ?? this.durationMs,
      isIncognito: isIncognito ?? this.isIncognito,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (encryptedText.present) {
      map['encrypted_text'] = Variable<String>(encryptedText.value);
    }
    if (ivBase64.present) {
      map['iv_base64'] = Variable<String>(ivBase64.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (isIncognito.present) {
      map['is_incognito'] = Variable<bool>(isIncognito.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TranscriptionEntriesCompanion(')
          ..write('id: $id, ')
          ..write('encryptedText: $encryptedText, ')
          ..write('ivBase64: $ivBase64, ')
          ..write('timestamp: $timestamp, ')
          ..write('durationMs: $durationMs, ')
          ..write('isIncognito: $isIncognito')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TranscriptionEntriesTable transcriptionEntries =
      $TranscriptionEntriesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [transcriptionEntries];
}

typedef $$TranscriptionEntriesTableCreateCompanionBuilder =
    TranscriptionEntriesCompanion Function({
      Value<int> id,
      required String encryptedText,
      required String ivBase64,
      required DateTime timestamp,
      Value<int?> durationMs,
      Value<bool> isIncognito,
    });
typedef $$TranscriptionEntriesTableUpdateCompanionBuilder =
    TranscriptionEntriesCompanion Function({
      Value<int> id,
      Value<String> encryptedText,
      Value<String> ivBase64,
      Value<DateTime> timestamp,
      Value<int?> durationMs,
      Value<bool> isIncognito,
    });

class $$TranscriptionEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $TranscriptionEntriesTable> {
  $$TranscriptionEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get encryptedText => $composableBuilder(
    column: $table.encryptedText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ivBase64 => $composableBuilder(
    column: $table.ivBase64,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isIncognito => $composableBuilder(
    column: $table.isIncognito,
    builder: (column) => ColumnFilters(column),
  );
}

class $$TranscriptionEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $TranscriptionEntriesTable> {
  $$TranscriptionEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get encryptedText => $composableBuilder(
    column: $table.encryptedText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ivBase64 => $composableBuilder(
    column: $table.ivBase64,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isIncognito => $composableBuilder(
    column: $table.isIncognito,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$TranscriptionEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $TranscriptionEntriesTable> {
  $$TranscriptionEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get encryptedText => $composableBuilder(
    column: $table.encryptedText,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ivBase64 =>
      $composableBuilder(column: $table.ivBase64, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isIncognito => $composableBuilder(
    column: $table.isIncognito,
    builder: (column) => column,
  );
}

class $$TranscriptionEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TranscriptionEntriesTable,
          TranscriptionEntry,
          $$TranscriptionEntriesTableFilterComposer,
          $$TranscriptionEntriesTableOrderingComposer,
          $$TranscriptionEntriesTableAnnotationComposer,
          $$TranscriptionEntriesTableCreateCompanionBuilder,
          $$TranscriptionEntriesTableUpdateCompanionBuilder,
          (
            TranscriptionEntry,
            BaseReferences<
              _$AppDatabase,
              $TranscriptionEntriesTable,
              TranscriptionEntry
            >,
          ),
          TranscriptionEntry,
          PrefetchHooks Function()
        > {
  $$TranscriptionEntriesTableTableManager(
    _$AppDatabase db,
    $TranscriptionEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TranscriptionEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TranscriptionEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$TranscriptionEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> encryptedText = const Value.absent(),
                Value<String> ivBase64 = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<int?> durationMs = const Value.absent(),
                Value<bool> isIncognito = const Value.absent(),
              }) => TranscriptionEntriesCompanion(
                id: id,
                encryptedText: encryptedText,
                ivBase64: ivBase64,
                timestamp: timestamp,
                durationMs: durationMs,
                isIncognito: isIncognito,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String encryptedText,
                required String ivBase64,
                required DateTime timestamp,
                Value<int?> durationMs = const Value.absent(),
                Value<bool> isIncognito = const Value.absent(),
              }) => TranscriptionEntriesCompanion.insert(
                id: id,
                encryptedText: encryptedText,
                ivBase64: ivBase64,
                timestamp: timestamp,
                durationMs: durationMs,
                isIncognito: isIncognito,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TranscriptionEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TranscriptionEntriesTable,
      TranscriptionEntry,
      $$TranscriptionEntriesTableFilterComposer,
      $$TranscriptionEntriesTableOrderingComposer,
      $$TranscriptionEntriesTableAnnotationComposer,
      $$TranscriptionEntriesTableCreateCompanionBuilder,
      $$TranscriptionEntriesTableUpdateCompanionBuilder,
      (
        TranscriptionEntry,
        BaseReferences<
          _$AppDatabase,
          $TranscriptionEntriesTable,
          TranscriptionEntry
        >,
      ),
      TranscriptionEntry,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TranscriptionEntriesTableTableManager get transcriptionEntries =>
      $$TranscriptionEntriesTableTableManager(_db, _db.transcriptionEntries);
}
