import 'dart:convert';

import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/drift.dart';

class DriftWorkbenchRepository(final AleraDatabase _db)
    implements WorkbenchRepository {
  @override
  Future<List<Workspace>> listWorkspaces(String projectId) async {
    final rows =
        await (_db.select(_db.workspacesTable)
              ..where(
                (table) =>
                    table.projectId.equals(projectId) &
                    table.status.equals(WorkspaceStatus.active.name),
              )
              ..orderBy(<OrderingTerm Function(WorkspacesTable)>[
                (table) => OrderingTerm.asc(table.createdAt),
              ]))
            .get();
    return _sortWorkspaces(rows.map(_workspaceFromRow).toList(growable: false));
  }

  @override
  Stream<List<Workspace>> watchWorkspaces(String projectId) {
    final query = _db.select(_db.workspacesTable)
      ..where(
        (table) =>
            table.projectId.equals(projectId) &
            table.status.equals(WorkspaceStatus.active.name),
      )
      ..orderBy(<OrderingTerm Function(WorkspacesTable)>[
        (table) => OrderingTerm.asc(table.createdAt),
      ]);
    return query.watch().map(
      (rows) =>
          _sortWorkspaces(rows.map(_workspaceFromRow).toList(growable: false)),
    );
  }

  @override
  Future<Workspace?> findWorkspaceById(String workspaceId) async {
    final row = await (_db.select(
      _db.workspacesTable,
    )..where((table) => table.id.equals(workspaceId))).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _workspaceFromRow(row);
  }

  @override
  Future<Workspace> upsertWorkspace(Workspace workspace) async {
    await _db
        .into(_db.workspacesTable)
        .insertOnConflictUpdate(_workspaceCompanion(workspace));
    return workspace;
  }

  @override
  Future<Workspace> setWorkspacePinned(
    String workspaceId,
    bool isPinned,
  ) async {
    final workspace = await findWorkspaceById(workspaceId);
    if (workspace == null) {
      throw StateError('Workspace not found: $workspaceId');
    }
    final updated = workspace.copyWith(isPinned: isPinned);
    await upsertWorkspace(updated);
    return updated;
  }

  @override
  Future<void> removeWorkspace(
    String workspaceId, {
    bool cascadeTabs = true,
  }) async {
    await _db.transaction(() async {
      if (cascadeTabs) {
        await (_db.delete(
          _db.workspaceTabsTable,
        )..where((table) => table.workspaceId.equals(workspaceId))).go();
      }
      await (_db.delete(
        _db.workbenchLayoutsTable,
      )..where((table) => table.workspaceId.equals(workspaceId))).go();
      await (_db.delete(
        _db.workspacesTable,
      )..where((table) => table.id.equals(workspaceId))).go();
    });
  }

  @override
  Future<void> removeWorkspacesForProject(String projectId) async {
    await _db.transaction(() async {
      final workspaceIds =
          await (_db.select(_db.workspacesTable)
                ..where((table) => table.projectId.equals(projectId)))
              .map((row) => row.id)
              .get();
      if (workspaceIds.isEmpty) {
        return;
      }
      await (_db.delete(
        _db.workspaceTabsTable,
      )..where((table) => table.workspaceId.isIn(workspaceIds))).go();
      await (_db.delete(
        _db.workbenchLayoutsTable,
      )..where((table) => table.workspaceId.isIn(workspaceIds))).go();
      await (_db.delete(
        _db.workspacesTable,
      )..where((table) => table.id.isIn(workspaceIds))).go();
    });
  }

  @override
  Future<List<WorkspaceTabRecord>> listWorkspaceTabs(String workspaceId) async {
    final rows =
        await (_db.select(_db.workspaceTabsTable)
              ..where((table) => table.workspaceId.equals(workspaceId))
              ..orderBy(<OrderingTerm Function(WorkspaceTabsTable)>[
                (table) => OrderingTerm.asc(table.createdAt),
              ]))
            .get();
    return rows.map(_workspaceTabFromRow).toList(growable: false);
  }

  @override
  Stream<List<WorkspaceTabRecord>> watchWorkspaceTabs(String workspaceId) {
    final query = _db.select(_db.workspaceTabsTable)
      ..where((table) => table.workspaceId.equals(workspaceId))
      ..orderBy(<OrderingTerm Function(WorkspaceTabsTable)>[
        (table) => OrderingTerm.asc(table.createdAt),
      ]);
    return query.watch().map(
      (rows) => rows.map(_workspaceTabFromRow).toList(growable: false),
    );
  }

  @override
  Future<WorkspaceTabRecord?> findWorkspaceTabById(String tabId) async {
    final row = await (_db.select(
      _db.workspaceTabsTable,
    )..where((table) => table.id.equals(tabId))).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _workspaceTabFromRow(row);
  }

  @override
  Future<WorkspaceTabRecord> upsertWorkspaceTab(
    WorkspaceTabRecord tab, {
    bool manualRename = false,
  }) async {
    await _db
        .into(_db.workspaceTabsTable)
        .insertOnConflictUpdate(_workspaceTabCompanion(tab));
    return tab;
  }

  @override
  Future<void> removeWorkspaceTab(String tabId) async {
    await (_db.delete(
      _db.workspaceTabsTable,
    )..where((table) => table.id.equals(tabId))).go();
  }

  @override
  Future<void> removeWorkspaceTabsForWorkspace(String workspaceId) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.workspaceTabsTable,
      )..where((table) => table.workspaceId.equals(workspaceId))).go();
      await (_db.delete(
        _db.workbenchLayoutsTable,
      )..where((table) => table.workspaceId.equals(workspaceId))).go();
    });
  }

  @override
  Future<WorkbenchLayout?> findWorkbenchLayout(String workspaceId) async {
    final row =
        await (_db.select(_db.workbenchLayoutsTable)
              ..where((table) => table.workspaceId.equals(workspaceId)))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }
    final decoded = jsonDecode(row.dataJson);
    if (decoded is! Map) {
      throw StateError('Workbench layout payload must be a JSON object.');
    }
    return WorkbenchLayout.fromJson(Map<String, Object?>.from(decoded));
  }

  @override
  Future<WorkbenchLayout> upsertWorkbenchLayout(WorkbenchLayout layout) async {
    await _db
        .into(_db.workbenchLayoutsTable)
        .insertOnConflictUpdate(
          WorkbenchLayoutsTableCompanion.insert(
            workspaceId: layout.workspaceId,
            dataJson: jsonEncode(layout.toMap()),
          ),
        );
    return layout;
  }

  @override
  Future<void> removeWorkbenchLayout(String workspaceId) async {
    await (_db.delete(
      _db.workbenchLayoutsTable,
    )..where((table) => table.workspaceId.equals(workspaceId))).go();
  }
}

Workspace _workspaceFromRow(WorkspacesTableData row) {
  return Workspace(
    id: row.id,
    projectId: row.projectId,
    name: row.name,
    path: row.path,
    createdAt: row.createdAt.toUtc(),
    updatedAt: row.updatedAt.toUtc(),
    kind: WorkspaceKind.values.firstWhere((kind) => kind.name == row.kind),
    status: WorkspaceStatus.values.firstWhere(
      (status) => status.name == row.status,
    ),
    branch: row.branch?.isEmpty ?? true ? null : row.branch,
    sourceBranch: row.sourceBranch?.isEmpty ?? true ? null : row.sourceBranch,
    reusesExistingBranch: row.reusesExistingBranch,
    isPinned: row.isPinned,
    hostId: 'local',
  );
}

WorkspacesTableCompanion _workspaceCompanion(Workspace workspace) {
  return WorkspacesTableCompanion.insert(
    id: workspace.id,
    projectId: workspace.projectId,
    name: workspace.name,
    branch: Value(workspace.branch),
    path: workspace.path,
    createdAt: workspace.createdAt.toUtc(),
    updatedAt: workspace.updatedAt.toUtc(),
    kind: workspace.kind.name,
    status: workspace.status.name,
    sourceBranch: Value(workspace.sourceBranch),
    reusesExistingBranch: Value(workspace.reusesExistingBranch),
    isPinned: Value(workspace.isPinned),
  );
}

WorkspaceTabRecord _workspaceTabFromRow(WorkspaceTabsTableData row) {
  final decoded = jsonDecode(row.payloadJson);
  final payload = decoded is Map<String, dynamic>
      ? Map<String, Object?>.from(decoded)
      : const <String, Object?>{};
  return WorkspaceTabRecord(
    id: row.id,
    workspaceId: row.workspaceId,
    kind: WorkspaceTabKind.fromJson(row.kind),
    title: row.title,
    createdAt: row.createdAt.toUtc(),
    updatedAt: row.updatedAt.toUtc(),
    payload: payload,
  );
}

WorkspaceTabsTableCompanion _workspaceTabCompanion(WorkspaceTabRecord tab) {
  return WorkspaceTabsTableCompanion(
    id: Value(tab.id),
    workspaceId: Value(tab.workspaceId),
    kind: Value(tab.kind.key),
    title: Value(tab.title),
    createdAt: Value(tab.createdAt.toUtc()),
    updatedAt: Value(tab.updatedAt.toUtc()),
    payloadJson: Value(jsonEncode(tab.payload)),
  );
}

List<Workspace> _sortWorkspaces(List<Workspace> workspaces) {
  workspaces.sort((left, right) {
    if (left.isMain != right.isMain) {
      return left.isMain ? -1 : 1;
    }
    final createdAt = left.createdAt.compareTo(right.createdAt);
    if (createdAt != 0) {
      return createdAt;
    }
    return left.name.toLowerCase().compareTo(right.name.toLowerCase());
  });
  return List<Workspace>.unmodifiableOf(workspaces);
}
