import 'package:alera/src/features/workbench/infra/drift_workspace_activity_repository.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AleraDatabase db;
  late DriftWorkspaceActivityRepository repository;

  setUp(() async {
    db = AleraDatabase(executor: NativeDatabase.memory());
    repository = DriftWorkspaceActivityRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('loadAll returns an empty map for a fresh database', () async {
    expect(await repository.loadAll(), isEmpty);
  });

  test('upsertAll inserts and updates entries', () async {
    final first = DateTime.utc(2026, 7, 4, 10);
    final second = DateTime.utc(2026, 7, 4, 12);

    await repository.upsertAll(<String, DateTime>{'w-1': first});
    await repository.upsertAll(<String, DateTime>{'w-1': second, 'w-2': first});

    final loaded = await repository.loadAll();
    expect(loaded, <String, DateTime>{'w-1': second, 'w-2': first});
  });

  test('remove deletes only the targeted workspace', () async {
    final at = DateTime.utc(2026, 7, 4, 10);
    await repository.upsertAll(<String, DateTime>{'w-1': at, 'w-2': at});

    await repository.remove('w-1');

    expect(await repository.loadAll(), <String, DateTime>{'w-2': at});
  });
}
