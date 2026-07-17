import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/drift_workbench_repository.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DriftWorkbenchRepository', () {
    test(
      'lists and watches only active workspaces with normalized fields',
      () async {
        final db = AleraDatabase(executor: NativeDatabase.memory());
        addTearDown(db.close);
        final repository = DriftWorkbenchRepository(db);
        final now = DateTime.utc(2026, 5, 25, 12);
        final mainWorkspace = _workspace(
          id: 'workspace-main',
          projectId: 'project-1',
          now: now.add(const Duration(hours: 1)),
          kind: WorkspaceKind.main,
          branch: '',
          sourceBranch: '',
        );
        final linkedEarly = _workspace(
          id: 'workspace-linked-early',
          projectId: 'project-1',
          now: now,
          kind: WorkspaceKind.linked,
          branch: 'feature/a',
          sourceBranch: 'main',
          reusesExistingBranch: true,
        );
        final linkedLate = _workspace(
          id: 'workspace-linked-late',
          projectId: 'project-1',
          now: now.add(const Duration(days: 1)),
          kind: WorkspaceKind.linked,
          branch: 'feature/b',
          sourceBranch: 'main',
        );

        await repository.upsertWorkspace(linkedLate);
        await repository.upsertWorkspace(mainWorkspace);
        await repository.upsertWorkspace(linkedEarly);
        await _insertWorkspace(
          db,
          _workspace(
            id: 'workspace-removed',
            projectId: 'project-1',
            now: now,
            kind: WorkspaceKind.linked,
            status: WorkspaceStatus.removed,
            branch: 'feature/removed',
          ),
        );

        final listed = await repository.listWorkspaces('project-1');
        final watched = await repository.watchWorkspaces('project-1').first;

        expect(listed.map((workspace) => workspace.id), <String>[
          mainWorkspace.id,
          linkedEarly.id,
          linkedLate.id,
        ]);
        expect(watched, listed);
        expect(listed.first.branch, isNull);
        expect(listed.first.sourceBranch, isNull);
        expect(listed[1].reusesExistingBranch, isTrue);
      },
    );

    test('persists workspace pin state', () async {
      final db = AleraDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DriftWorkbenchRepository(db);
      final workspace = _workspace(
        id: 'workspace-pinned',
        projectId: 'project-1',
        now: DateTime.utc(2026, 7, 16),
      );
      await repository.upsertWorkspace(workspace);

      final pinned = await repository.setWorkspacePinned(workspace.id, true);
      final stored = await repository.findWorkspaceById(workspace.id);

      expect(pinned.isPinned, isTrue);
      expect(stored?.isPinned, isTrue);
    });

    test(
      'removes one workspace without cascading tabs when requested',
      () async {
        final db = AleraDatabase(executor: NativeDatabase.memory());
        addTearDown(db.close);
        final repository = DriftWorkbenchRepository(db);
        final now = DateTime.utc(2026, 5, 25, 12);
        final workspace = _workspace(
          id: 'workspace-1',
          projectId: 'project-1',
          now: now,
        );
        final tab = _tab(id: 'tab-1', workspaceId: workspace.id, now: now);
        final layout = WorkbenchLayout.single(
          workspaceId: workspace.id,
          tabIds: <String>[tab.id],
        );

        await repository.upsertWorkspace(workspace);
        await repository.upsertWorkspaceTab(tab);
        await repository.upsertWorkbenchLayout(layout);

        await repository.removeWorkspace(workspace.id, cascadeTabs: false);

        expect(await repository.findWorkspaceById(workspace.id), isNull);
        expect(await repository.findWorkbenchLayout(workspace.id), isNull);
        expect(await repository.findWorkspaceTabById(tab.id), isNotNull);
      },
    );

    test('removes one workspace and its tabs by default', () async {
      final db = AleraDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DriftWorkbenchRepository(db);
      final now = DateTime.utc(2026, 5, 25, 12);
      final workspace = _workspace(
        id: 'workspace-1',
        projectId: 'project-1',
        now: now,
      );
      final tab = _tab(id: 'tab-1', workspaceId: workspace.id, now: now);

      await repository.upsertWorkspace(workspace);
      await repository.upsertWorkspaceTab(tab);

      await repository.removeWorkspace(workspace.id);

      expect(await repository.findWorkspaceById(workspace.id), isNull);
      expect(await repository.findWorkspaceTabById(tab.id), isNull);
    });

    test(
      'round-trips workspace tabs and normalizes invalid payload json',
      () async {
        final db = AleraDatabase(executor: NativeDatabase.memory());
        addTearDown(db.close);
        final repository = DriftWorkbenchRepository(db);
        final now = DateTime.utc(2026, 5, 25, 12);
        final workspace = _workspace(
          id: 'workspace-1',
          projectId: 'project-1',
          now: now,
        );
        final tab = WorkspaceTabRecord(
          id: 'tab-1',
          workspaceId: workspace.id,
          kind: WorkspaceTabKind.browser,
          title: 'Preview',
          payload: const <String, Object?>{'path': 'readme.md'},
          createdAt: now,
          updatedAt: now,
        );

        await repository.upsertWorkspace(workspace);
        await repository.upsertWorkspaceTab(tab);
        await _insertWorkspaceTabRow(
          db,
          workspaceId: workspace.id,
          tabId: 'tab-invalid',
          payloadJson: '[]',
          now: now,
        );

        final listed = await repository.listWorkspaceTabs(workspace.id);
        final watched = await repository.watchWorkspaceTabs(workspace.id).first;
        final restored = await repository.findWorkspaceTabById(tab.id);
        final normalized = await repository.findWorkspaceTabById('tab-invalid');

        expect(listed, watched);
        expect(restored?.kind, WorkspaceTabKind.browser);
        expect(restored?.payload, <String, Object?>{'path': 'readme.md'});
        expect(normalized?.payload, const <String, Object?>{});

        await repository.removeWorkspaceTab(tab.id);
        await repository.removeWorkspaceTabsForWorkspace(workspace.id);
        expect(await repository.findWorkspaceTabById(tab.id), isNull);
        expect(await repository.findWorkspaceTabById('tab-invalid'), isNull);
      },
    );

    test(
      'round-trips workbench layouts and rejects non-object payloads',
      () async {
        final db = AleraDatabase(executor: NativeDatabase.memory());
        addTearDown(db.close);
        final repository = DriftWorkbenchRepository(db);
        final now = DateTime.utc(2026, 5, 25, 12);
        final workspace = _workspace(
          id: 'workspace-1',
          projectId: 'project-1',
          now: now,
        );
        final layout =
            WorkbenchLayout.single(
              workspaceId: workspace.id,
              tabIds: const <String>['tab-1'],
            ).splitWithGroup(
              targetGroupId: WorkbenchLayout.defaultGroupId(workspace.id),
              zone: WorkbenchDropZone.right,
              newGroup: WorkbenchPaneGroup(
                id: 'group-2',
                tabIds: const <String>['tab-2'],
                activeTabId: 'tab-2',
              ),
            );

        await repository.upsertWorkspace(workspace);
        await repository.upsertWorkbenchLayout(layout);

        expect(await repository.findWorkbenchLayout(workspace.id), layout);

        await repository.removeWorkbenchLayout(workspace.id);
        expect(await repository.findWorkbenchLayout(workspace.id), isNull);

        await db
            .into(db.workbenchLayoutsTable)
            .insert(
              WorkbenchLayoutsTableCompanion.insert(
                workspaceId: workspace.id,
                dataJson: '[]',
              ),
            );

        await expectLater(
          repository.findWorkbenchLayout(workspace.id),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('removes every workspace, tab, and layout for one project', () async {
      final db = AleraDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DriftWorkbenchRepository(db);
      final now = DateTime.utc(2026, 5, 25, 12);
      final firstWorkspace = _workspace(
        id: 'workspace-1',
        projectId: 'project-1',
        now: now,
      );
      final secondWorkspace = _workspace(
        id: 'workspace-2',
        projectId: 'project-1',
        now: now.add(const Duration(minutes: 1)),
      );
      final otherWorkspace = _workspace(
        id: 'workspace-3',
        projectId: 'project-2',
        now: now,
      );
      final firstTab = _tab(
        id: 'tab-1',
        workspaceId: firstWorkspace.id,
        now: now,
      );
      final secondTab = _tab(
        id: 'tab-2',
        workspaceId: secondWorkspace.id,
        now: now,
      );
      final otherTab = _tab(
        id: 'tab-3',
        workspaceId: otherWorkspace.id,
        now: now,
      );

      await repository.upsertWorkspace(firstWorkspace);
      await repository.upsertWorkspace(secondWorkspace);
      await repository.upsertWorkspace(otherWorkspace);
      await repository.upsertWorkspaceTab(firstTab);
      await repository.upsertWorkspaceTab(secondTab);
      await repository.upsertWorkspaceTab(otherTab);
      await repository.upsertWorkbenchLayout(
        WorkbenchLayout.single(
          workspaceId: firstWorkspace.id,
          tabIds: <String>[firstTab.id],
        ),
      );
      await repository.upsertWorkbenchLayout(
        WorkbenchLayout.single(
          workspaceId: secondWorkspace.id,
          tabIds: <String>[secondTab.id],
        ),
      );
      await repository.upsertWorkbenchLayout(
        WorkbenchLayout.single(
          workspaceId: otherWorkspace.id,
          tabIds: <String>[otherTab.id],
        ),
      );

      await repository.removeWorkspacesForProject('project-1');

      expect(await repository.listWorkspaces('project-1'), isEmpty);
      expect(await repository.findWorkspaceById(otherWorkspace.id), isNotNull);
      expect(await repository.findWorkspaceTabById(firstTab.id), isNull);
      expect(await repository.findWorkspaceTabById(secondTab.id), isNull);
      expect(await repository.findWorkspaceTabById(otherTab.id), isNotNull);
      expect(await repository.findWorkbenchLayout(firstWorkspace.id), isNull);
      expect(await repository.findWorkbenchLayout(secondWorkspace.id), isNull);
      expect(
        await repository.findWorkbenchLayout(otherWorkspace.id),
        isNotNull,
      );
    });

    test('sorts linked workspaces by name when createdAt ties', () async {
      final db = AleraDatabase(executor: NativeDatabase.memory());
      addTearDown(db.close);
      final repository = DriftWorkbenchRepository(db);
      final now = DateTime.utc(2026, 5, 25, 12);
      final zebra = _workspace(
        id: 'workspace-zebra',
        projectId: 'project-1',
        now: now,
        kind: WorkspaceKind.linked,
        branch: 'feature/zebra',
      ).copyWith(name: 'zebra');
      final alpha = _workspace(
        id: 'workspace-alpha',
        projectId: 'project-1',
        now: now,
        kind: WorkspaceKind.linked,
        branch: 'feature/alpha',
      ).copyWith(name: 'alpha');

      await repository.upsertWorkspace(zebra);
      await repository.upsertWorkspace(alpha);

      expect(
        (await repository.listWorkspaces(
          'project-1',
        )).map((workspace) => workspace.name),
        <String>['alpha', 'zebra'],
      );
    });
  });
}

Workspace _workspace({
  required String id,
  required String projectId,
  required DateTime now,
  WorkspaceKind kind = WorkspaceKind.main,
  WorkspaceStatus status = WorkspaceStatus.active,
  String? branch = 'main',
  String? sourceBranch,
  bool reusesExistingBranch = false,
}) {
  return Workspace(
    id: id,
    projectId: projectId,
    name: id,
    branch: branch,
    sourceBranch: sourceBranch,
    path: '/repo/$projectId/$id',
    createdAt: now,
    updatedAt: now,
    kind: kind,
    status: status,
    reusesExistingBranch: reusesExistingBranch,
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
          reusesExistingBranch: Value(workspace.reusesExistingBranch),
          isPinned: Value(workspace.isPinned),
        ),
      );
}

Future<void> _insertWorkspaceTabRow(
  AleraDatabase db, {
  required String workspaceId,
  required String tabId,
  required String payloadJson,
  required DateTime now,
}) {
  return db
      .into(db.workspaceTabsTable)
      .insert(
        WorkspaceTabsTableCompanion.insert(
          id: tabId,
          workspaceId: workspaceId,
          kind: WorkspaceTabKind.terminal.key,
          title: tabId,
          createdAt: now.toUtc(),
          updatedAt: now.toUtc(),
          payloadJson: Value(payloadJson),
        ),
      );
}
