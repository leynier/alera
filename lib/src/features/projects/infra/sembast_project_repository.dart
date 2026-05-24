import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/shared/infra/storage/sembast_database.dart';
import 'package:sembast/sembast.dart';

class SembastProjectRepository implements ProjectRepository {
  SembastProjectRepository(this._db);

  final Database _db;

  @override
  Future<List<Project>> listAll() async {
    final records = await AleraStores.projects.find(
      _db,
      finder: Finder(sortOrders: <SortOrder>[SortOrder('updatedAt', false)]),
    );
    return records
        .map((r) => Project.fromJson(r.value))
        .toList(growable: false);
  }

  @override
  Stream<List<Project>> watchAll() {
    return AleraStores.projects
        .query(
          finder: Finder(
            sortOrders: <SortOrder>[SortOrder('updatedAt', false)],
          ),
        )
        .onSnapshots(_db)
        .map(
          (records) => records
              .map((r) => Project.fromJson(r.value))
              .toList(growable: false),
        );
  }

  @override
  Future<Project> add(Project project) async {
    await AleraStores.projects.record(project.id).put(_db, project.toJson());
    return project;
  }

  @override
  Future<Project> update(Project project) async {
    await AleraStores.projects.record(project.id).put(_db, project.toJson());
    return project;
  }

  @override
  Future<void> remove(String projectId) async {
    await _db.transaction((txn) async {
      await AleraStores.projects.record(projectId).delete(txn);
      final workspaceRecords = await AleraStores.workbenchWorkspaces.find(
        txn,
        finder: Finder(filter: Filter.equals('projectId', projectId)),
      );
      for (final workspaceRecord in workspaceRecords) {
        await _deleteWorkspaceRecords(txn, workspaceRecord.key);
      }
    });
  }

  Future<void> _deleteWorkspaceRecords(
    Transaction txn,
    String workspaceId,
  ) async {
    await AleraStores.workbenchWorkspaces.record(workspaceId).delete(txn);
    await AleraStores.workbenchLayouts.record(workspaceId).delete(txn);

    final tabRecords = await AleraStores.legacyTerminalTabs.find(
      txn,
      finder: Finder(filter: Filter.equals('workspaceId', workspaceId)),
    );
    for (final tabRecord in tabRecords) {
      await AleraStores.legacyTerminalTabs.record(tabRecord.key).delete(txn);
    }

    final workspaceTabRecords = await AleraStores.workspaceTabs.find(
      txn,
      finder: Finder(filter: Filter.equals('workspaceId', workspaceId)),
    );
    for (final tabRecord in workspaceTabRecords) {
      await AleraStores.workspaceTabs.record(tabRecord.key).delete(txn);
    }
  }
}
