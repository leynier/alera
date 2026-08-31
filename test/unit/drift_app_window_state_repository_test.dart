import 'package:alera/src/features/app_window/domain/app_window_state.dart';
import 'package:alera/src/features/app_window/infra/drift_app_window_state_repository.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriftAppWindowStateRepository', () {
    test('saves, loads, and clears singleton window state', () async {
      final db = AleraDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DriftAppWindowStateRepository(db);
      const state = AppWindowState(
        normalBounds: AppWindowBounds(
          left: 10,
          top: 20,
          width: 1300,
          height: 800,
        ),
        maximized: true,
      );

      await repository.save(state);
      expect(await repository.load(), state);

      await repository.clear();
      expect(await repository.load(), isNull);
    });

    test('returns null for corrupt persisted JSON', () async {
      final db = AleraDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DriftAppWindowStateRepository(db);

      await db
          .into(db.appWindowStateTable)
          .insert(
            AppWindowStateTableCompanion(
              id: const Value(1),
              dataJson: const Value('{not json'),
              updatedAt: Value(.utc(2026)),
            ),
          );

      expect(await repository.load(), isNull);
    });
  });
}
