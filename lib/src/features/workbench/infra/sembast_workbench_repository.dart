import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/domain/terminal_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workbench_tab_record.dart';
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
      final tabs = await AleraStores.terminalTabs.find(
        txn,
        finder: Finder(filter: Filter.equals('workspaceId', workspaceId)),
      );
      for (final tab in tabs) {
        await AleraStores.terminalTabs.record(tab.key).delete(txn);
      }
      final workbenchTabs = await AleraStores.workbenchTabs.find(
        txn,
        finder: Finder(filter: Filter.equals('workspaceId', workspaceId)),
      );
      for (final tab in workbenchTabs) {
        await AleraStores.workbenchTabs.record(tab.key).delete(txn);
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
        final tabs = await AleraStores.terminalTabs.find(
          txn,
          finder: Finder(filter: Filter.equals('workspaceId', workspaceId)),
        );
        for (final tab in tabs) {
          await AleraStores.terminalTabs.record(tab.key).delete(txn);
        }
        final workbenchTabs = await AleraStores.workbenchTabs.find(
          txn,
          finder: Finder(filter: Filter.equals('workspaceId', workspaceId)),
        );
        for (final tab in workbenchTabs) {
          await AleraStores.workbenchTabs.record(tab.key).delete(txn);
        }
        await AleraStores.workbenchLayouts.record(workspaceId).delete(txn);
      }
    });
  }

  @override
  Future<List<WorkbenchTabRecord>> listWorkbenchTabs(String workspaceId) async {
    final records = await AleraStores.workbenchTabs.find(
      _db,
      finder: Finder(
        filter: Filter.equals('workspaceId', workspaceId),
        sortOrders: <SortOrder>[SortOrder('createdAt', true)],
      ),
    );
    if (records.isNotEmpty) {
      return records
          .map((record) => WorkbenchTabRecord.fromJson(record.value))
          .toList(growable: false);
    }
    return _migrateLegacyTerminalTabs(workspaceId);
  }

  @override
  Stream<List<WorkbenchTabRecord>> watchWorkbenchTabs(String workspaceId) {
    return AleraStores.workbenchTabs
        .query(
          finder: Finder(
            filter: Filter.equals('workspaceId', workspaceId),
            sortOrders: <SortOrder>[SortOrder('createdAt', true)],
          ),
        )
        .onSnapshots(_db)
        .map(
          (records) => records
              .map((record) => WorkbenchTabRecord.fromJson(record.value))
              .toList(growable: false),
        );
  }

  @override
  Future<WorkbenchTabRecord?> findWorkbenchTabById(String tabId) async {
    final record = await AleraStores.workbenchTabs.record(tabId).get(_db);
    if (record == null) {
      final legacyRecord = await AleraStores.terminalTabs
          .record(tabId)
          .get(_db);
      if (legacyRecord == null) {
        return null;
      }
      final migrated = WorkbenchTabRecord.fromJson(legacyRecord);
      await upsertWorkbenchTab(migrated);
      return migrated;
    }
    return WorkbenchTabRecord.fromJson(record);
  }

  @override
  Future<WorkbenchTabRecord> upsertWorkbenchTab(WorkbenchTabRecord tab) async {
    await AleraStores.workbenchTabs.record(tab.id).put(_db, tab.toJson());
    return tab;
  }

  @override
  Future<void> removeWorkbenchTab(String tabId) async {
    await _db.transaction((txn) async {
      await AleraStores.workbenchTabs.record(tabId).delete(txn);
      await AleraStores.terminalTabs.record(tabId).delete(txn);
    });
  }

  @override
  Future<void> removeWorkbenchTabsForWorkspace(String workspaceId) async {
    await _db.transaction((txn) async {
      final workbenchTabs = await AleraStores.workbenchTabs.find(
        txn,
        finder: Finder(filter: Filter.equals('workspaceId', workspaceId)),
      );
      for (final tab in workbenchTabs) {
        await AleraStores.workbenchTabs.record(tab.key).delete(txn);
      }
      final tabs = await AleraStores.terminalTabs.find(
        txn,
        finder: Finder(filter: Filter.equals('workspaceId', workspaceId)),
      );
      for (final tab in tabs) {
        await AleraStores.terminalTabs.record(tab.key).delete(txn);
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

  @override
  Future<List<TerminalTabRecord>> listTerminalTabs(String workspaceId) {
    return listWorkbenchTabs(workspaceId);
  }

  @override
  Stream<List<TerminalTabRecord>> watchTerminalTabs(String workspaceId) {
    return watchWorkbenchTabs(workspaceId);
  }

  @override
  Future<TerminalTabRecord?> findTerminalTabById(String tabId) {
    return findWorkbenchTabById(tabId);
  }

  @override
  Future<TerminalTabRecord> upsertTerminalTab(TerminalTabRecord tab) {
    return upsertWorkbenchTab(tab);
  }

  @override
  Future<void> removeTerminalTab(String tabId) {
    return removeWorkbenchTab(tabId);
  }

  @override
  Future<void> removeTerminalTabsForWorkspace(String workspaceId) {
    return removeWorkbenchTabsForWorkspace(workspaceId);
  }

  Future<List<WorkbenchTabRecord>> _migrateLegacyTerminalTabs(
    String workspaceId,
  ) async {
    final legacyRecords = await AleraStores.terminalTabs.find(
      _db,
      finder: Finder(
        filter: Filter.equals('workspaceId', workspaceId),
        sortOrders: <SortOrder>[SortOrder('createdAt', true)],
      ),
    );
    if (legacyRecords.isEmpty) {
      return const <WorkbenchTabRecord>[];
    }
    final migrated = legacyRecords
        .map((record) => WorkbenchTabRecord.fromJson(record.value))
        .toList(growable: false);
    await _db.transaction((txn) async {
      for (final tab in migrated) {
        await AleraStores.workbenchTabs.record(tab.id).put(txn, tab.toJson());
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
