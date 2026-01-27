// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transcription_entry.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types

extension GetTranscriptionEntryCollection on Isar {
  IsarCollection<TranscriptionEntry> get transcriptionEntrys =>
      this.collection();
}

const TranscriptionEntrySchema = CollectionSchema(
  name: r'TranscriptionEntry',
  id: 3721183978667788913,
  properties: {
    r'durationMs': PropertySchema(
      id: 0,
      name: r'durationMs',
      type: IsarType.long,
    ),
    r'encryptedText': PropertySchema(
      id: 1,
      name: r'encryptedText',
      type: IsarType.string,
    ),
    r'isIncognito': PropertySchema(
      id: 2,
      name: r'isIncognito',
      type: IsarType.bool,
    ),
    r'ivBase64': PropertySchema(
      id: 3,
      name: r'ivBase64',
      type: IsarType.string,
    ),
    r'timestamp': PropertySchema(
      id: 4,
      name: r'timestamp',
      type: IsarType.dateTime,
    )
  },
  estimateSize: _transcriptionEntryEstimateSize,
  serialize: _transcriptionEntrySerialize,
  deserialize: _transcriptionEntryDeserialize,
  deserializeProp: _transcriptionEntryDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},
  getId: _transcriptionEntryGetId,
  getLinks: _transcriptionEntryGetLinks,
  attach: _transcriptionEntryAttach,
  version: '3.1.0+1',
);

int _transcriptionEntryEstimateSize(
  TranscriptionEntry object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.encryptedText.length * 3;
  bytesCount += 3 + object.ivBase64.length * 3;
  return bytesCount;
}

void _transcriptionEntrySerialize(
  TranscriptionEntry object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.durationMs);
  writer.writeString(offsets[1], object.encryptedText);
  writer.writeBool(offsets[2], object.isIncognito);
  writer.writeString(offsets[3], object.ivBase64);
  writer.writeDateTime(offsets[4], object.timestamp);
}

TranscriptionEntry _transcriptionEntryDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = TranscriptionEntry(
    durationMs: reader.readLongOrNull(offsets[0]),
    encryptedText: reader.readString(offsets[1]),
    isIncognito: reader.readBoolOrNull(offsets[2]) ?? false,
    ivBase64: reader.readString(offsets[3]),
    timestamp: reader.readDateTime(offsets[4]),
  );
  object.id = id;
  return object;
}

P _transcriptionEntryDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLongOrNull(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readBoolOrNull(offset) ?? false) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readDateTime(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _transcriptionEntryGetId(TranscriptionEntry object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _transcriptionEntryGetLinks(
    TranscriptionEntry object) {
  return [];
}

void _transcriptionEntryAttach(
    IsarCollection<dynamic> col, Id id, TranscriptionEntry object) {
  object.id = id;
}

extension TranscriptionEntryQueryWhereSort
    on QueryBuilder<TranscriptionEntry, TranscriptionEntry, QWhere> {
  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension TranscriptionEntryQueryWhere
    on QueryBuilder<TranscriptionEntry, TranscriptionEntry, QWhereClause> {
  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterWhereClause>
      idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: id,
        upper: id,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterWhereClause>
      idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterWhereClause>
      idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterWhereClause>
      idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterWhereClause>
      idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(
        lower: lowerId,
        includeLower: includeLower,
        upper: upperId,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension TranscriptionEntryQueryFilter
    on QueryBuilder<TranscriptionEntry, TranscriptionEntry, QFilterCondition> {
  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      durationMsIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNull(
        property: r'durationMs',
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      durationMsIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(const FilterCondition.isNotNull(
        property: r'durationMs',
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      durationMsEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'durationMs',
        value: value,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      durationMsGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'durationMs',
        value: value,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      durationMsLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'durationMs',
        value: value,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      durationMsBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'durationMs',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      encryptedTextEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'encryptedText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      encryptedTextGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'encryptedText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      encryptedTextLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'encryptedText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      encryptedTextBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'encryptedText',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      encryptedTextStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'encryptedText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      encryptedTextEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'encryptedText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      encryptedTextContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'encryptedText',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      encryptedTextMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'encryptedText',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      encryptedTextIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'encryptedText',
        value: '',
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      encryptedTextIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'encryptedText',
        value: '',
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'id',
        value: value,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'id',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      isIncognitoEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'isIncognito',
        value: value,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      ivBase64EqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ivBase64',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      ivBase64GreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'ivBase64',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      ivBase64LessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'ivBase64',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      ivBase64Between(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'ivBase64',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      ivBase64StartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.startsWith(
        property: r'ivBase64',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      ivBase64EndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.endsWith(
        property: r'ivBase64',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      ivBase64Contains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.contains(
        property: r'ivBase64',
        value: value,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      ivBase64Matches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.matches(
        property: r'ivBase64',
        wildcard: pattern,
        caseSensitive: caseSensitive,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      ivBase64IsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'ivBase64',
        value: '',
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      ivBase64IsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        property: r'ivBase64',
        value: '',
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      timestampEqualTo(DateTime value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.equalTo(
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      timestampGreaterThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.greaterThan(
        include: include,
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      timestampLessThan(
    DateTime value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.lessThan(
        include: include,
        property: r'timestamp',
        value: value,
      ));
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterFilterCondition>
      timestampBetween(
    DateTime lower,
    DateTime upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(FilterCondition.between(
        property: r'timestamp',
        lower: lower,
        includeLower: includeLower,
        upper: upper,
        includeUpper: includeUpper,
      ));
    });
  }
}

extension TranscriptionEntryQueryObject
    on QueryBuilder<TranscriptionEntry, TranscriptionEntry, QFilterCondition> {}

extension TranscriptionEntryQueryLinks
    on QueryBuilder<TranscriptionEntry, TranscriptionEntry, QFilterCondition> {}

extension TranscriptionEntryQuerySortBy
    on QueryBuilder<TranscriptionEntry, TranscriptionEntry, QSortBy> {
  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      sortByDurationMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'durationMs', Sort.asc);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      sortByDurationMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'durationMs', Sort.desc);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      sortByEncryptedText() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'encryptedText', Sort.asc);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      sortByEncryptedTextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'encryptedText', Sort.desc);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      sortByIsIncognito() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isIncognito', Sort.asc);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      sortByIsIncognitoDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isIncognito', Sort.desc);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      sortByIvBase64() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ivBase64', Sort.asc);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      sortByIvBase64Desc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ivBase64', Sort.desc);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      sortByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.asc);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      sortByTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.desc);
    });
  }
}

extension TranscriptionEntryQuerySortThenBy
    on QueryBuilder<TranscriptionEntry, TranscriptionEntry, QSortThenBy> {
  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      thenByDurationMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'durationMs', Sort.asc);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      thenByDurationMsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'durationMs', Sort.desc);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      thenByEncryptedText() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'encryptedText', Sort.asc);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      thenByEncryptedTextDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'encryptedText', Sort.desc);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      thenByIsIncognito() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isIncognito', Sort.asc);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      thenByIsIncognitoDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'isIncognito', Sort.desc);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      thenByIvBase64() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ivBase64', Sort.asc);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      thenByIvBase64Desc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ivBase64', Sort.desc);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      thenByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.asc);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QAfterSortBy>
      thenByTimestampDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'timestamp', Sort.desc);
    });
  }
}

extension TranscriptionEntryQueryWhereDistinct
    on QueryBuilder<TranscriptionEntry, TranscriptionEntry, QDistinct> {
  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QDistinct>
      distinctByDurationMs() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'durationMs');
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QDistinct>
      distinctByEncryptedText({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'encryptedText',
          caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QDistinct>
      distinctByIsIncognito() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'isIncognito');
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QDistinct>
      distinctByIvBase64({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ivBase64', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<TranscriptionEntry, TranscriptionEntry, QDistinct>
      distinctByTimestamp() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'timestamp');
    });
  }
}

extension TranscriptionEntryQueryProperty
    on QueryBuilder<TranscriptionEntry, TranscriptionEntry, QQueryProperty> {
  QueryBuilder<TranscriptionEntry, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<TranscriptionEntry, int?, QQueryOperations>
      durationMsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'durationMs');
    });
  }

  QueryBuilder<TranscriptionEntry, String, QQueryOperations>
      encryptedTextProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'encryptedText');
    });
  }

  QueryBuilder<TranscriptionEntry, bool, QQueryOperations>
      isIncognitoProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'isIncognito');
    });
  }

  QueryBuilder<TranscriptionEntry, String, QQueryOperations>
      ivBase64Property() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ivBase64');
    });
  }

  QueryBuilder<TranscriptionEntry, DateTime, QQueryOperations>
      timestampProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'timestamp');
    });
  }
}
