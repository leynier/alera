import 'dart:convert';

import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/infra/drift_project_repository.dart';
import 'package:alera/src/features/projects/infra/drift_project_config_repository.dart';
import 'package:alera/src/features/projects/domain/project_config.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriftProjectRepository', () {
    test('add, list, watch, and update round-trip projects', () async {
      final db = AleraDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DriftProjectRepository(db);
      final now = DateTime.utc(2026, 5, 23);
      final early = _project('project-1', now);
      final late = _project('project-2', now.add(const Duration(days: 1)));

      await repository.add(early);
      await repository.add(late);

      expect(
        (await repository.listAll()).map((project) => project.id),
        <String>[late.id, early.id],
      );
      expect(
        (await repository.watchAll().first).map((project) => project.id),
        <String>[late.id, early.id],
      );

      final updated = late.copyWith(name: 'project-2-renamed');
      final returned = await repository.update(updated);

      expect(returned, updated);
      expect((await _projectRow(db, updated.id))?.name, 'project-2-renamed');
    });

    test(
      'remove cascades workspace tabs and layouts for project workspaces',
      () async {
        final db = AleraDatabase(executor: NativeDatabase.memory());
        addTearDown(db.close);
        final repository = DriftProjectRepository(db);
        final configRepository = DriftProjectConfigRepository(db);
        final now = DateTime.utc(2026, 5, 23);
        final project = _project('project-1', now);
        final otherProject = _project('project-2', now);
        final workspace = _workspace(
          id: 'workspace-1',
          projectId: project.id,
          now: now,
        );
        final otherWorkspace = _workspace(
          id: 'workspace-2',
          projectId: otherProject.id,
          now: now,
        );
        final tab = _tab(id: 'tab-1', workspaceId: workspace.id, now: now);
        final otherTab = _tab(
          id: 'tab-2',
          workspaceId: otherWorkspace.id,
          now: now,
        );

        await repository.add(project);
        await repository.add(otherProject);
        await configRepository.save(
          projectId: project.id,
          config: const ProjectConfig(
            worktree: WorktreeSetupConfig(setup: <String>['make bootstrap']),
          ),
          updatedAt: now,
        );
        await configRepository.save(
          projectId: otherProject.id,
          config: const ProjectConfig(
            worktree: WorktreeSetupConfig(setup: <String>['make keep']),
          ),
          updatedAt: now,
        );
        await _insertWorkspace(db, workspace);
        await _insertWorkspace(db, otherWorkspace);
        await _insertWorkspaceTab(db, tab);
        await _insertWorkspaceTab(db, otherTab);
        await _insertWorkbenchLayout(
          db,
          WorkbenchLayout.single(
            workspaceId: workspace.id,
            tabIds: <String>[tab.id],
          ),
        );
        await _insertWorkbenchLayout(
          db,
          WorkbenchLayout.single(
            workspaceId: otherWorkspace.id,
            tabIds: <String>[otherTab.id],
          ),
        );

        await repository.remove(project.id);

        expect(await _projectRow(db, project.id), isNull);
        expect(await configRepository.findByProjectId(project.id), isNull);
        expect(await _workspaceRow(db, workspace.id), isNull);
        expect(await _workspaceTabRow(db, tab.id), isNull);
        expect(await _workbenchLayoutRow(db, workspace.id), isNull);
        expect(await _projectRow(db, otherProject.id), isNotNull);
        expect(
          await configRepository.findByProjectId(otherProject.id),
          isNotNull,
        );
        expect(await _workspaceRow(db, otherWorkspace.id), isNotNull);
        expect(await _workspaceTabRow(db, otherTab.id), isNotNull);
        expect(await _workbenchLayoutRow(db, otherWorkspace.id), isNotNull);
      },
    );
  });
}

Project _project(String id, DateTime now) {
  return Project(
    id: id,
    name: id,
    repoPath: '/repo/$id',
    createdAt: now,
    updatedAt: now,
  );
}

Workspace _workspace({
  required String id,
  required String projectId,
  required DateTime now,
}) {
  return Workspace(
    id: id,
    projectId: projectId,
    name: id,
    branch: 'main',
    path: '/repo/$projectId',
    createdAt: now,
    updatedAt: now,
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
  );
}

WorkspaceTabRecord _tab({
  required String id,
  required String workspaceId,
  required DateTime now,
}) {
  return WorkspaceTabRecord(
    id: id,
    workspaceId: workspaceId,
    title: id,
    createdAt: now,
    updatedAt: now,
  );
}

Future<void> _insertWorkspace(AleraDatabase db, Workspace workspace) {
  return db
      .into(db.workspacesTable)
      .insert(
        WorkspacesTableCompanion.insert(
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
        ),
      );
}

Future<void> _insertWorkspaceTab(AleraDatabase db, WorkspaceTabRecord tab) {
  return db
      .into(db.workspaceTabsTable)
      .insert(
        WorkspaceTabsTableCompanion.insert(
          id: tab.id,
          workspaceId: tab.workspaceId,
          kind: tab.kind.key,
          title: tab.title,
          createdAt: tab.createdAt.toUtc(),
          updatedAt: tab.updatedAt.toUtc(),
          payloadJson: Value(jsonEncode(tab.payload)),
        ),
      );
}

Future<void> _insertWorkbenchLayout(AleraDatabase db, WorkbenchLayout layout) {
  return db
      .into(db.workbenchLayoutsTable)
      .insert(
        WorkbenchLayoutsTableCompanion.insert(
          workspaceId: layout.workspaceId,
          dataJson: jsonEncode(layout.toMap()),
        ),
      );
}

Future<ProjectsTableData?> _projectRow(AleraDatabase db, String projectId) {
  return (db.select(
    db.projectsTable,
  )..where((table) => table.id.equals(projectId))).getSingleOrNull();
}

Future<WorkspacesTableData?> _workspaceRow(
  AleraDatabase db,
  String workspaceId,
) {
  return (db.select(
    db.workspacesTable,
  )..where((table) => table.id.equals(workspaceId))).getSingleOrNull();
}

Future<WorkspaceTabsTableData?> _workspaceTabRow(
  AleraDatabase db,
  String tabId,
) {
  return (db.select(
    db.workspaceTabsTable,
  )..where((table) => table.id.equals(tabId))).getSingleOrNull();
}

Future<WorkbenchLayoutsTableData?> _workbenchLayoutRow(
  AleraDatabase db,
  String workspaceId,
) {
  return (db.select(
    db.workbenchLayoutsTable,
  )..where((table) => table.workspaceId.equals(workspaceId))).getSingleOrNull();
}
