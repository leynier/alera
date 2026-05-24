import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/domain/terminal_tab_record.dart';
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
    final record = await AleraStores.workbenchWorkspaces.record(workspaceId).get(
      _db,
    );
    if (record == null) {
      return null;
    }
    return Workspace.fromJson(record);
  }

  @override
  Future<Workspace> upsertWorkspace(Workspace workspace) async {
    await AleraStores.workbenchWorkspaces.record(workspace.id).put(
      _db,
      workspace.toJson(),
    );
    return workspace;
  }

  @override
  Future<void> removeWorkspace(
    String workspaceId, {
    bool cascadeTabs = true,
  }) async {
    await _db.transaction((txn) async {
      await AleraStores.workbenchWorkspaces.record(workspaceId).delete(txn);
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
      }
    });
  }

  @override
  Future<List<TerminalTabRecord>> listTerminalTabs(String workspaceId) async {
    final records = await AleraStores.terminalTabs.find(
      _db,
      finder: Finder(
        filter: Filter.equals('workspaceId', workspaceId),
        sortOrders: <SortOrder>[SortOrder('createdAt', true)],
      ),
    );
    return records
        .map((record) => TerminalTabRecord.fromJson(record.value))
        .toList(growable: false);
  }

  @override
  Stream<List<TerminalTabRecord>> watchTerminalTabs(String workspaceId) {
    return AleraStores.terminalTabs
        .query(
          finder: Finder(
            filter: Filter.equals('workspaceId', workspaceId),
            sortOrders: <SortOrder>[SortOrder('createdAt', true)],
          ),
        )
        .onSnapshots(_db)
        .map(
          (records) => records
              .map((record) => TerminalTabRecord.fromJson(record.value))
              .toList(growable: false),
        );
  }

  @override
  Future<TerminalTabRecord?> findTerminalTabById(String tabId) async {
    final record = await AleraStores.terminalTabs.record(tabId).get(_db);
    if (record == null) {
      return null;
    }
    return TerminalTabRecord.fromJson(record);
  }

  @override
  Future<TerminalTabRecord> upsertTerminalTab(TerminalTabRecord tab) async {
    await AleraStores.terminalTabs.record(tab.id).put(_db, tab.toJson());
    return tab;
  }

  @override
  Future<void> removeTerminalTab(String tabId) async {
    await AleraStores.terminalTabs.record(tabId).delete(_db);
  }

  @override
  Future<void> removeTerminalTabsForWorkspace(String workspaceId) async {
    await _db.transaction((txn) async {
      final tabs = await AleraStores.terminalTabs.find(
        txn,
        finder: Finder(filter: Filter.equals('workspaceId', workspaceId)),
      );
      for (final tab in tabs) {
        await AleraStores.terminalTabs.record(tab.key).delete(txn);
      }
    });
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
