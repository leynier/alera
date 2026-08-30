import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/dart_constructor_compatibility.dart';

void main() {
  test(
    'primary enum constructors retain values and serialization metadata',
    () {
      expect(RecordRole.reader.label, 'Reader');
      expect(RecordRole.writer.label, 'Writer');
      expect(RecordRole.reader.toValue(), 'read');
      expect(RecordRoleMapper.fromValue('write'), RecordRole.writer);
      expect(RecordRole.values, [RecordRole.reader, RecordRole.writer]);
    },
  );

  test('mapper preserves inherited fields, defaults, const and copyWith', () {
    const original = ChildRecord('a');
    expect(identical(original, const ChildRecord('a')), isTrue);
    expect(original.toMap(), {
      'record_id': 'a',
      'label': 'default',
      'values': <String>[],
    });
    expect(ChildRecordMapper.fromMap({'record_id': 'b'}).label, 'default');
    expect(original.copyWith(label: 'updated').id, 'a');
  });

  test('Riverpod generated family keeps its defaults', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(counterProvider()), 3);
    expect(container.read(counterProvider(initial: 7)), 7);
  });

  test(
    'Drift keeps schema and row defaults with a primary constructor',
    () async {
      final database = ProbeDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.into(database.rows).insert(RowsCompanion.insert());
      final row = await database.select(database.rows).getSingle();
      expect(row.id, 1);
      expect(row.value, 'default');
    },
  );
}
