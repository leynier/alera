import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/infra/storage/sembast_database.dart';
import 'package:sembast/sembast.dart';

class SembastWorkbenchRepository implements WorkbenchRepository {
  SembastWorkbenchRepository(this._db);

  final Database _db;

  @override
  Future<List<Workspace>> listWorkspaces(String projectId) async {
    final records = await AleraStores.workbenchWorkspaces.find(
      _db,
      finder: Finder(
        filter: Filter.equals('projectId', projectId),
        sortOrders: <SortOrder>[SortOrder('createdAt', true)],
      ),
    );
    return _sortWorkspaces(
      records
          .map((record) => Workspace.fromJson(record.value))
          .where((workspace) => workspace.isActive)
          .toList(),
    );
  }

  @override
  Stream<List<Workspace>> watchWorkspaces(String projectId) {
    return AleraStores.workbenchWorkspaces
        .query(
          finder: Finder(
            filter: Filter.equals('projectId', projectId),
            sortOrders: <SortOrder>[SortOrder('createdAt', true)],
          ),
        )
        .onSnapshots(_db)
        .map(
          (records) => _sortWorkspaces(
            records
                .map((record) => Workspace.fromJson(record.value))
                .where((workspace) => workspace.isActive)
                .toList(growable: false),
          ),
        );
  }

  @override
  Future<Workspace?> findWorkspaceById(String workspaceId) async {
    final record = await AleraStores.workbenchWorkspaces
        .record(workspaceId)
        .get(_db);
    if (record == null) {
      return null;
    }
    return Workspace.fromJson(record);
  }

  @override
  Future<Workspace> upsertWorkspace(Workspace workspace) async {
    await AleraStores.workbenchWorkspaces
        .record(workspace.id)
        .put(_db, workspace.toJson());
    return workspace;
  }

  @override
  Future<void> removeWorkspace(
    String workspaceId, {
    bool cascadeTabs = true,
  }) async {
    await _db.transaction((txn) async {
      await AleraStores.workbenchWorkspaces.record(workspaceId).delete(txn);
      await AleraStores.workbenchLayouts.record(workspaceId).delete(txn);
      if (!cascadeTabs) {
        return;
      }
      final tabs = await AleraStores.legacyTerminalTabs.find(
        txn,
        finder: Finder(filter: Filter.equals('workspaceId', workspaceId)),
      );
      for (final tab in tabs) {
        await AleraStores.legacyTerminalTabs.record(tab.key).delete(txn);
      }
      final workspaceTabs = await AleraStores.workspaceTabs.find(
        txn,
        finder: Finder(filter: Filter.equals('workspaceId', workspaceId)),
      );
      for (final tab in workspaceTabs) {
        await AleraStores.workspaceTabs.record(tab.key).delete(txn);
      }
    });
  }

  @override
  Future<void> removeWorkspacesForProject(String projectId) async {
    await _db.transaction((txn) async {
      final workspaces = await AleraStores.workbenchWorkspaces.find(
        txn,
        finder: Finder(filter: Filter.equals('projectId', projectId)),
      );
      for (final workspace in workspaces) {
        final workspaceId = workspace.key;
        await AleraStores.workbenchWorkspaces.record(workspaceId).delete(txn);
        final tabs = await AleraStores.legacyTerminalTabs.find(
          txn,
          finder: Finder(filter: Filter.equals('workspaceId', workspaceId)),
        );
        for (final tab in tabs) {
          await AleraStores.legacyTerminalTabs.record(tab.key).delete(txn);
        }
        final workspaceTabs = await AleraStores.workspaceTabs.find(
          txn,
          finder: Finder(filter: Filter.equals('workspaceId', workspaceId)),
        );
        for (final tab in workspaceTabs) {
          await AleraStores.workspaceTabs.record(tab.key).delete(txn);
        }
        await AleraStores.workbenchLayouts.record(workspaceId).delete(txn);
      }
    });
  }

  @override
  Future<List<WorkspaceTabRecord>> listWorkspaceTabs(String workspaceId) async {
    final records = await AleraStores.workspaceTabs.find(
      _db,
      finder: Finder(
        filter: Filter.equals('workspaceId', workspaceId),
        sortOrders: <SortOrder>[SortOrder('createdAt', true)],
      ),
    );
    if (records.isNotEmpty) {
      return records
          .map((record) => WorkspaceTabRecord.fromJson(record.value))
          .toList(growable: false);
    }
    return _migrateLegacyTerminalTabs(workspaceId);
  }

  @override
  Stream<List<WorkspaceTabRecord>> watchWorkspaceTabs(String workspaceId) {
    return AleraStores.workspaceTabs
        .query(
          finder: Finder(
            filter: Filter.equals('workspaceId', workspaceId),
            sortOrders: <SortOrder>[SortOrder('createdAt', true)],
          ),
        )
        .onSnapshots(_db)
        .map(
          (records) => records
              .map((record) => WorkspaceTabRecord.fromJson(record.value))
              .toList(growable: false),
        );
  }

  @override
  Future<WorkspaceTabRecord?> findWorkspaceTabById(String tabId) async {
    final record = await AleraStores.workspaceTabs.record(tabId).get(_db);
    if (record == null) {
      final legacyRecord = await AleraStores.legacyTerminalTabs
          .record(tabId)
          .get(_db);
      if (legacyRecord == null) {
        return null;
      }
      final migrated = WorkspaceTabRecord.fromJson(legacyRecord);
      await upsertWorkspaceTab(migrated);
      return migrated;
    }
    return WorkspaceTabRecord.fromJson(record);
  }

  @override
  Future<WorkspaceTabRecord> upsertWorkspaceTab(WorkspaceTabRecord tab) async {
    await AleraStores.workspaceTabs.record(tab.id).put(_db, tab.toJson());
    return tab;
  }

  @override
  Future<void> removeWorkspaceTab(String tabId) async {
    await _db.transaction((txn) async {
      await AleraStores.workspaceTabs.record(tabId).delete(txn);
      await AleraStores.legacyTerminalTabs.record(tabId).delete(txn);
    });
  }

  @override
  Future<void> removeWorkspaceTabsForWorkspace(String workspaceId) async {
    await _db.transaction((txn) async {
      final workspaceTabs = await AleraStores.workspaceTabs.find(
        txn,
        finder: Finder(filter: Filter.equals('workspaceId', workspaceId)),
      );
      for (final tab in workspaceTabs) {
        await AleraStores.workspaceTabs.record(tab.key).delete(txn);
      }
      final tabs = await AleraStores.legacyTerminalTabs.find(
        txn,
        finder: Finder(filter: Filter.equals('workspaceId', workspaceId)),
      );
      for (final tab in tabs) {
        await AleraStores.legacyTerminalTabs.record(tab.key).delete(txn);
      }
    });
  }

  @override
  Future<WorkbenchLayout?> findWorkbenchLayout(String workspaceId) async {
    final record = await AleraStores.workbenchLayouts
        .record(workspaceId)
        .get(_db);
    if (record == null) {
      return null;
    }
    return WorkbenchLayout.fromJson(record);
  }

  @override
  Future<WorkbenchLayout> upsertWorkbenchLayout(WorkbenchLayout layout) async {
    await AleraStores.workbenchLayouts
        .record(layout.workspaceId)
        .put(_db, layout.toJson());
    return layout;
  }

  @override
  Future<void> removeWorkbenchLayout(String workspaceId) async {
    await AleraStores.workbenchLayouts.record(workspaceId).delete(_db);
  }

  Future<List<WorkspaceTabRecord>> _migrateLegacyTerminalTabs(
    String workspaceId,
  ) async {
    final legacyRecords = await AleraStores.legacyTerminalTabs.find(
      _db,
      finder: Finder(
        filter: Filter.equals('workspaceId', workspaceId),
        sortOrders: <SortOrder>[SortOrder('createdAt', true)],
      ),
    );
    if (legacyRecords.isEmpty) {
      return const <WorkspaceTabRecord>[];
    }
    final migrated = legacyRecords
        .map((record) => WorkspaceTabRecord.fromJson(record.value))
        .toList(growable: false);
    await _db.transaction((txn) async {
      for (final tab in migrated) {
        await AleraStores.workspaceTabs.record(tab.id).put(txn, tab.toJson());
      }
    });
    return migrated;
  }
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
  return List<Workspace>.unmodifiable(workspaces);
}
