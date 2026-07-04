import 'package:alera/src/features/workbench/application/workspace_activity_repository.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/drift.dart' show Value;

class DriftWorkspaceActivityRepository implements WorkspaceActivityRepository {
  DriftWorkspaceActivityRepository(this._db);

  final AleraDatabase _db;

  @override
  Future<Map<String, DateTime>> loadAll() async {
    final rows = await _db.select(_db.workspaceActivityTable).get();
    // Drift round-trips DateTime in local time; normalize to UTC so loaded
    // values compare cleanly against the UTC timestamps recorded in memory.
    return <String, DateTime>{
      for (final row in rows) row.workspaceId: row.lastActivityAt.toUtc(),
    };
  }

  @override
  Future<void> upsertAll(Map<String, DateTime> entries) async {
    if (entries.isEmpty) {
      return;
    }
    await _db.batch((batch) {
      batch.insertAllOnConflictUpdate(
        _db.workspaceActivityTable,
        <WorkspaceActivityTableCompanion>[
          for (final entry in entries.entries)
            WorkspaceActivityTableCompanion(
              workspaceId: Value(entry.key),
              lastActivityAt: Value(entry.value),
            ),
        ],
      );
    });
  }

  @override
  Future<void> remove(String workspaceId) async {
    await (_db.delete(
      _db.workspaceActivityTable,
    )..where((table) => table.workspaceId.equals(workspaceId))).go();
  }
}
