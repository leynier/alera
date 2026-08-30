// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dart_constructor_compatibility.dart';

// ignore_for_file: type=lint
class $RowsTable extends Rows with TableInfo<$RowsTable, Row> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RowsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('default'),
  );
  @override
  List<GeneratedColumn> get $columns => [id, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<Row> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Row map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Row(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $RowsTable createAlias(String alias) {
    return $RowsTable(attachedDatabase, alias);
  }
}

class Row extends DataClass implements Insertable<Row> {
  final int id;
  final String value;
  const Row({required this.id, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['value'] = Variable<String>(value);
    return map;
  }

  RowsCompanion toCompanion(bool nullToAbsent) {
    return RowsCompanion(id: Value(id), value: Value(value));
  }

  factory Row.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Row(
      id: serializer.fromJson<int>(json['id']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'value': serializer.toJson<String>(value),
    };
  }

  Row copyWith({int? id, String? value}) =>
      Row(id: id ?? this.id, value: value ?? this.value);
  Row copyWithCompanion(RowsCompanion data) {
    return Row(
      id: data.id.present ? data.id.value : this.id,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Row(')
          ..write('id: $id, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Row && other.id == this.id && other.value == this.value);
}

class RowsCompanion extends UpdateCompanion<Row> {
  final Value<int> id;
  final Value<String> value;
  const RowsCompanion({
    this.id = const Value.absent(),
    this.value = const Value.absent(),
  });
  RowsCompanion.insert({
    this.id = const Value.absent(),
    this.value = const Value.absent(),
  });
  static Insertable<Row> custom({
    Expression<int>? id,
    Expression<String>? value,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (value != null) 'value': value,
    });
  }

  RowsCompanion copyWith({Value<int>? id, Value<String>? value}) {
    return RowsCompanion(id: id ?? this.id, value: value ?? this.value);
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RowsCompanion(')
          ..write('id: $id, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }
}

abstract class _$ProbeDatabase extends GeneratedDatabase {
  _$ProbeDatabase(QueryExecutor e) : super(e);
  $ProbeDatabaseManager get managers => $ProbeDatabaseManager(this);
  late final $RowsTable rows = $RowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [rows];
}

typedef $$RowsTableCreateCompanionBuilder = RowsCompanion Function({
  Value<int> id,
  Value<String> value,
});
typedef $$RowsTableUpdateCompanionBuilder = RowsCompanion Function({
  Value<int> id,
  Value<String> value,
});

class $$RowsTableFilterComposer extends Composer<_$ProbeDatabase, $RowsTable> {
  $$RowsTableFilterComposer({
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

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RowsTableOrderingComposer
    extends Composer<_$ProbeDatabase, $RowsTable> {
  $$RowsTableOrderingComposer({
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

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RowsTableAnnotationComposer
    extends Composer<_$ProbeDatabase, $RowsTable> {
  $$RowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$RowsTableTableManager
    extends
        RootTableManager<
          _$ProbeDatabase,
          $RowsTable,
          Row,
          $$RowsTableFilterComposer,
          $$RowsTableOrderingComposer,
          $$RowsTableAnnotationComposer,
          $$RowsTableCreateCompanionBuilder,
          $$RowsTableUpdateCompanionBuilder,
          (Row, BaseReferences<_$ProbeDatabase, $RowsTable, Row>),
          Row,
          PrefetchHooks Function()
        > {
  $$RowsTableTableManager(_$ProbeDatabase db, $RowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> value = const Value.absent(),
          }) => RowsCompanion(id: id, value: value),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> value = const Value.absent(),
          }) => RowsCompanion.insert(id: id, value: value),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RowsTableProcessedTableManager =
    ProcessedTableManager<
      _$ProbeDatabase,
      $RowsTable,
      Row,
      $$RowsTableFilterComposer,
      $$RowsTableOrderingComposer,
      $$RowsTableAnnotationComposer,
      $$RowsTableCreateCompanionBuilder,
      $$RowsTableUpdateCompanionBuilder,
      (Row, BaseReferences<_$ProbeDatabase, $RowsTable, Row>),
      Row,
      PrefetchHooks Function()
    >;

class $ProbeDatabaseManager {
  final _$ProbeDatabase _db;
  $ProbeDatabaseManager(this._db);
  $$RowsTableTableManager get rows => $$RowsTableTableManager(_db, _db.rows);
}

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(Counter)
final counterProvider = CounterFamily._();

final class CounterProvider extends $NotifierProvider<Counter, int> {
  CounterProvider._({
    required CounterFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'counterProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$counterHash();

  @override
  String toString() {
    return r'counterProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  Counter create() => Counter();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CounterProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$counterHash() => r'3336925384cc49a3c3afc850aeb03ac7a5bef534';

final class CounterFamily extends $Family
    with $ClassFamilyOverride<Counter, int, int, int, int> {
  CounterFamily._()
    : super(
        retry: null,
        name: r'counterProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  CounterProvider call({int initial = 3}) =>
      CounterProvider._(argument: initial, from: this);

  @override
  String toString() => r'counterProvider';
}

abstract class _$Counter extends $Notifier<int> {
  late final _$args = ref.$arg as int;
  int get initial => _$args;

  int build({int initial = 3});
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(initial: _$args));
  }
}
