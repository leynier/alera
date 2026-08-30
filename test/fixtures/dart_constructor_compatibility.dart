import 'package:dart_mappable/dart_mappable.dart';
import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'dart_constructor_compatibility.g.dart';
part 'dart_constructor_compatibility.mapper.dart';

@MappableEnum()
enum RecordRole(final String label) {
  @MappableValue('read')
  reader('Reader'),
  @MappableValue('write')
  writer('Writer'),
}

@MappableClass()
class const BaseRecord(@MappableField(key: 'record_id') final String id)
    with BaseRecordMappable;

@MappableClass()
class const ChildRecord(
  super.id, {
  final String label = 'default',
  final List<String> values = const [],
}) extends BaseRecord with ChildRecordMappable;

class Rows extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get value => text().withDefault(const Constant('default'))();
}

@DriftDatabase(tables: [Rows])
class ProbeDatabase(super.executor) extends _$ProbeDatabase {
  @override
  int get schemaVersion => 1;
}

@riverpod
class Counter extends _$Counter {
  new();

  @override
  int build({int initial = 3}) => initial;
}
