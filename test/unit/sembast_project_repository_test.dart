import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/infra/sembast_project_repository.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/infra/storage/sembast_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  group('SembastProjectRepository', () {
    test(
      'remove cascades workspace tabs and layouts for project workspaces',
      () async {
        final db = await openAleraDb(
          factory: databaseFactoryMemory,
          path:
              'sembast_project_repository_test_${DateTime.now().microsecondsSinceEpoch}.db',
        );
        addTearDown(db.close);
        final repository = SembastProjectRepository(db);
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
        final legacyTab = _tab(
          id: 'legacy-tab-1',
          workspaceId: workspace.id,
          now: now,
        );
        final otherTab = _tab(
          id: 'tab-2',
          workspaceId: otherWorkspace.id,
          now: now,
        );

        await repository.add(project);
        await repository.add(otherProject);
        await AleraStores.workbenchWorkspaces
            .record(workspace.id)
            .put(db, workspace.toJson());
        await AleraStores.workbenchWorkspaces
            .record(otherWorkspace.id)
            .put(db, otherWorkspace.toJson());
        await AleraStores.workspaceTabs.record(tab.id).put(db, tab.toJson());
        await AleraStores.legacyTerminalTabs
            .record(legacyTab.id)
            .put(db, legacyTab.toJson());
        await AleraStores.workspaceTabs
            .record(otherTab.id)
            .put(db, otherTab.toJson());
        await AleraStores.workbenchLayouts
            .record(workspace.id)
            .put(
              db,
              WorkbenchLayout.single(
                workspaceId: workspace.id,
                tabIds: <String>[tab.id],
              ).toJson(),
            );
        await AleraStores.workbenchLayouts
            .record(otherWorkspace.id)
            .put(
              db,
              WorkbenchLayout.single(
                workspaceId: otherWorkspace.id,
                tabIds: <String>[otherTab.id],
              ).toJson(),
            );

        await repository.remove(project.id);

        expect(await AleraStores.projects.record(project.id).get(db), isNull);
        expect(
          await AleraStores.workbenchWorkspaces.record(workspace.id).get(db),
          isNull,
        );
        expect(await AleraStores.workspaceTabs.record(tab.id).get(db), isNull);
        expect(
          await AleraStores.legacyTerminalTabs.record(legacyTab.id).get(db),
          isNull,
        );
        expect(
          await AleraStores.workbenchLayouts.record(workspace.id).get(db),
          isNull,
        );
        expect(
          await AleraStores.projects.record(otherProject.id).get(db),
          isNotNull,
        );
        expect(
          await AleraStores.workbenchWorkspaces
              .record(otherWorkspace.id)
              .get(db),
          isNotNull,
        );
        expect(
          await AleraStores.workspaceTabs.record(otherTab.id).get(db),
          isNotNull,
        );
        expect(
          await AleraStores.workbenchLayouts.record(otherWorkspace.id).get(db),
          isNotNull,
        );
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
