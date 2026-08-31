import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/infra/drift_workbench_view_prefs_repository.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriftWorkbenchViewPrefsRepository', () {
    test('restores GPUI preferences without resetting unrelated fields', () async {
      final db = AleraDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DriftWorkbenchViewPrefsRepository(db);
      final encoded = await File('experiments/alera-gpui/tests/fixtures/workbench_view_prefs.json').readAsString();
      await db.into(db.workbenchViewPrefsTable).insert(
        WorkbenchViewPrefsTableCompanion(id: const Value(1), dataJson: Value(encoded)),
      );
      final restored = await repository.load();
      expect(restored.gitDiffViewMode, GitDiffViewMode.flat);
      expect(restored.groupBy, WorkbenchGroupBy.none);
      expect(restored.sidebarWidth, 412);
      expect(restored.rightSidebarWidth, 360);
      expect(restored.activeContextPanelTab, WorkbenchContextPanelTab.search);
      expect(restored.expandedWorkspaceIds, <String>{'workspace-1'});
      expect(restored.selectedProjectIds, <String>{'project-1'});
      expect(restored.sourceControlRootByWorkspaceId, <String, String>{'folder-workspace': 'src'});
    });

    test('returns defaults for missing or invalid rows', () async {
      final db = AleraDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DriftWorkbenchViewPrefsRepository(db);

      expect(await repository.load(), WorkbenchViewPrefs.defaults);

      await db
          .into(db.workbenchViewPrefsTable)
          .insert(
            WorkbenchViewPrefsTableCompanion(
              id: const Value(1),
              dataJson: Value(jsonEncode(<Object?>['invalid'])),
            ),
          );
      expect(await repository.load(), WorkbenchViewPrefs.defaults);
    });

    test('loads and saves the current-schema JSON object', () async {
      final db = AleraDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DriftWorkbenchViewPrefsRepository(db);
      final prefs = WorkbenchViewPrefs.defaults.copyWith(
        groupBy: WorkbenchGroupBy.none,
        selectedProjectIds: <String>{'project-1'},
        expandedWorkspaceIds: <String>{'workspace-1'},
      );

      await repository.save(prefs);
      final restored = await repository.load();

      expect(restored, prefs);

      await db
          .into(db.workbenchViewPrefsTable)
          .insertOnConflictUpdate(
            WorkbenchViewPrefsTableCompanion(
              id: const Value(1),
              dataJson: Value(jsonEncode(prefs.toMap())),
            ),
          );
      expect(await repository.load(), prefs);
    });
  });
}
