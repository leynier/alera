import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/drift.dart';

class DriftProjectRepository implements ProjectRepository {
  DriftProjectRepository(this._db);

  final AleraDatabase _db;

  @override
  Future<List<Project>> listAll() async {
    final query = _db.select(_db.projectsTable)
      ..orderBy(<OrderingTerm Function(ProjectsTable)>[
        (table) => OrderingTerm.desc(table.updatedAt),
      ]);
    final rows = await query.get();
    return rows.map(_projectFromRow).toList(growable: false);
  }

  @override
  Stream<List<Project>> watchAll() {
    final query = _db.select(_db.projectsTable)
      ..orderBy(<OrderingTerm Function(ProjectsTable)>[
        (table) => OrderingTerm.desc(table.updatedAt),
      ]);
    return query.watch().map(
      (rows) => rows.map(_projectFromRow).toList(growable: false),
    );
  }

  @override
  Future<Project> add(Project project) async {
    await _db.into(_db.projectsTable).insert(_projectCompanion(project));
    return project;
  }

  @override
  Future<Project> update(Project project) async {
    await _db
        .into(_db.projectsTable)
        .insertOnConflictUpdate(_projectCompanion(project));
    return project;
  }

  @override
  Future<void> remove(String projectId) async {
    await _db.transaction(() async {
      final workspaceIds =
          await (_db.select(_db.workspacesTable)
                ..where((table) => table.projectId.equals(projectId)))
              .map((row) => row.id)
              .get();
      if (workspaceIds.isNotEmpty) {
        await (_db.delete(
          _db.workspaceTabsTable,
        )..where((table) => table.workspaceId.isIn(workspaceIds))).go();
        await (_db.delete(
          _db.workbenchLayoutsTable,
        )..where((table) => table.workspaceId.isIn(workspaceIds))).go();
        await (_db.delete(
          _db.workspacesTable,
        )..where((table) => table.id.isIn(workspaceIds))).go();
      }
      await (_db.delete(
        _db.projectsTable,
      )..where((table) => table.id.equals(projectId))).go();
      await (_db.delete(
        _db.projectConfigsTable,
      )..where((table) => table.projectId.equals(projectId))).go();
    });
  }
}

Project _projectFromRow(ProjectsTableData row) {
  return Project(
    id: row.id,
    name: row.name,
    repoPath: row.repoPath,
    createdAt: row.createdAt.toUtc(),
    updatedAt: row.updatedAt.toUtc(),
    kind: ProjectKind.values.firstWhere((kind) => kind.name == row.kind),
  );
}

ProjectsTableCompanion _projectCompanion(Project project) {
  return ProjectsTableCompanion.insert(
    id: project.id,
    name: project.name,
    repoPath: project.repoPath,
    createdAt: project.createdAt.toUtc(),
    updatedAt: project.updatedAt.toUtc(),
    kind: project.kind.name,
  );
}
