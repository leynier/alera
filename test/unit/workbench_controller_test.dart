import 'dart:async';
import 'dart:io';

import 'package:alera/src/app/dependencies.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workspace_tab_service.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_view_prefs_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('WorkbenchController', () {
    late _WorkbenchHarness harness;
    late WorkbenchController controller;

    setUp(() {
      harness = _WorkbenchHarness();
      controller = harness.controller;
    });

    tearDown(() async {
      await harness.dispose();
    });

    test(
      'bootstrap prepares the main workspace without selecting it',
      () async {
        await controller.bootstrap();
        await _flushUntil(
          () => controller.state.workspacesFor(harness.project.id).isNotEmpty,
        );

        expect(controller.state.activeProjectId, harness.project.id);
        expect(controller.state.activeWorkspace, isNull);
        final workspaces = controller.state.workspacesFor(harness.project.id);
        expect(workspaces.single.isMain, isTrue);
        expect(controller.state.tabsFor(workspaces.single.id), isEmpty);
        expect(controller.state.activeWorkspaceTab, isNull);
      },
    );

    test(
      'selecting a workspace with no tabs seeds the first terminal tab',
      () async {
        await controller.bootstrap();
        final workspace = await _selectMainWorkspace(controller, harness);

        expect(controller.state.activeWorkspaceId, workspace.id);
        expect(
          controller.state.tabsFor(workspace.id).map((tab) => tab.title),
          <String>['Terminal 1'],
        );
        expect(controller.state.activeWorkspaceTab?.title, 'Terminal 1');
      },
    );

    test('closing the last active tab deselects the workspace', () async {
      await controller.bootstrap();
      final workspace = await _selectMainWorkspace(controller, harness);

      final firstTab = controller.state.activeWorkspaceTab!;
      final secondTab = await controller.createTerminalTab(workspace);

      expect(controller.state.activeWorkspaceTab?.id, secondTab.id);

      await controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: secondTab.id,
      );
      await _flush();

      expect(controller.state.activeWorkspaceTab?.id, firstTab.id);

      await controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: firstTab.id,
      );
      await _flush();

      final tabs = controller.state.tabsFor(workspace.id);
      expect(tabs, isEmpty);
      expect(controller.state.activeWorkspace, isNull);
      expect(controller.state.activeWorkspaceTab, isNull);
      expect(controller.state.activeTabIdByWorkspace[workspace.id], isNull);
      expect(controller.state.layoutFor(workspace.id)?.activeTabId, isNull);
    });

    test(
      'closing the last tab of an inactive workspace keeps the active workspace',
      () async {
        await controller.bootstrap();
        final mainWorkspace = await _selectMainWorkspace(controller, harness);

        final linked = await controller.createWorkspace(
          project: harness.project,
          sourceBranch: 'main',
          newBranchName: 'feature/inactive-close',
        );
        await _flush();
        final linkedTab = controller.state.activeWorkspaceTab!;

        await controller.selectWorkspace(
          project: harness.project,
          workspace: mainWorkspace,
        );
        await _flush();
        expect(controller.state.activeWorkspaceId, mainWorkspace.id);

        await controller.closeWorkspaceTab(
          workspace: linked,
          tabId: linkedTab.id,
        );
        await _flush();

        expect(controller.state.tabsFor(linked.id), isEmpty);
        expect(controller.state.activeWorkspaceId, mainWorkspace.id);
      },
    );

    test('closing several tabs keeps the remaining tab active', () async {
      await controller.bootstrap();
      final workspace = await _selectMainWorkspace(controller, harness);
      final firstTab = controller.state.activeWorkspaceTab!;
      final secondTab = await controller.createTerminalTab(workspace);
      final thirdTab = await controller.createTerminalTab(workspace);
      await _flush();

      await controller.closeWorkspaceTabs(
        workspace: workspace,
        tabIds: <String>[secondTab.id, thirdTab.id],
      );
      await _flush();

      expect(
        controller.state.tabsFor(workspace.id).map((tab) => tab.id),
        <String>[firstTab.id],
      );
      expect(controller.state.activeWorkspaceId, workspace.id);
      expect(controller.state.activeWorkspaceTab?.id, firstTab.id);
      expect(
        controller.state.layoutFor(workspace.id)?.activeTabId,
        firstTab.id,
      );
    });

    test('renames project, workspace, and terminal tab in state', () async {
      await controller.bootstrap();
      await _flushUntil(
        () => controller.state.workspacesFor(harness.project.id).isNotEmpty,
      );

      await controller.renameProject(
        projectId: harness.project.id,
        name: '  Renamed project  ',
      );
      await _flush();
      expect(controller.state.projects.single.name, 'Renamed project');

      final workspace = await _selectMainWorkspace(controller, harness);
      await controller.renameWorkspace(
        workspaceId: workspace.id,
        name: '  Primary workspace  ',
      );
      await _flush();
      expect(
        controller.state.workspacesFor(harness.project.id).single.name,
        'Primary workspace',
      );

      final tab = controller.state.activeWorkspaceTab!;
      await controller.renameWorkspaceTab(
        tabId: tab.id,
        title: '  API server  ',
      );
      await _flush();
      expect(controller.state.activeWorkspaceTab?.title, 'API server');
      expect(controller.state.activeWorkspaceTab?.hasManualTitle, isTrue);
    });

    test(
      'deleting a workspace removes it from state without lingering',
      () async {
        await controller.bootstrap();
        await _flushUntil(
          () => controller.state.workspacesFor(harness.project.id).isNotEmpty,
        );
        final mainWorkspace = controller.state
            .workspacesFor(harness.project.id)
            .single;

        final linked = await controller.createWorkspace(
          project: harness.project,
          sourceBranch: 'main',
          newBranchName: 'feature/delete-me',
        );
        await _flush();
        expect(
          controller.state.workspacesFor(harness.project.id).map((w) => w.id),
          containsAll(<String>[mainWorkspace.id, linked.id]),
        );

        await controller.deleteWorkspace(
          project: harness.project,
          workspace: linked,
        );
        await _flush();

        expect(
          controller.state.workspacesFor(harness.project.id).map((w) => w.id),
          <String>[mainWorkspace.id],
        );
      },
    );

    test(
      'deleting the active workspace clears the workspace selection',
      () async {
        await controller.bootstrap();
        await _flushUntil(
          () => controller.state.workspacesFor(harness.project.id).isNotEmpty,
        );

        final linked = await controller.createWorkspace(
          project: harness.project,
          sourceBranch: 'main',
          newBranchName: 'feature/active',
        );
        await _flush();
        expect(controller.state.activeWorkspaceId, linked.id);
        expect(controller.state.activeProjectId, harness.project.id);

        await controller.deleteWorkspace(
          project: harness.project,
          workspace: linked,
        );
        await _flush();

        expect(controller.state.activeProjectId, harness.project.id);
        expect(controller.state.activeWorkspace, isNull);
      },
    );

    test('collapsing a project survives a later projects emission', () async {
      await controller.bootstrap();
      await _flush();
      expect(controller.state.expandedProjectIds, contains(harness.project.id));

      controller.toggleExpanded(harness.project.id);
      expect(
        controller.state.expandedProjectIds,
        isNot(contains(harness.project.id)),
      );

      final secondProject = await harness.addProject('project-2', 'Beta');
      await _flush();

      expect(
        controller.state.expandedProjectIds,
        isNot(contains(harness.project.id)),
      );
      expect(controller.state.expandedProjectIds, contains(secondProject.id));
    });

    test('splits a workspace group and preserves terminal tab ids', () async {
      await controller.bootstrap();
      final workspace = await _selectMainWorkspace(controller, harness);
      final firstTab = controller.state.activeWorkspaceTab!;
      final groupId = controller.state.layoutFor(workspace.id)!.activeGroupId;

      final secondTab = await controller.splitWorkbenchGroupWithTerminal(
        workspace: workspace,
        groupId: groupId,
        zone: WorkbenchDropZone.right,
      );
      await _flush();

      final layout = controller.state.layoutFor(workspace.id)!;
      expect(layout.root.axis, WorkbenchSplitAxis.horizontal);
      expect(layout.paneGroupIds, hasLength(2));
      expect(controller.state.tabsFor(workspace.id).map((tab) => tab.id), [
        firstTab.id,
        secondTab.id,
      ]);
      expect(layout.groupIdForTab(firstTab.id), groupId);
      expect(layout.groupIdForTab(secondTab.id), isNot(groupId));
      expect(controller.state.activeWorkspaceTab?.id, secondTab.id);
    });

    test(
      'moves a tab into another stack and collapses the empty source pane',
      () async {
        await controller.bootstrap();
        final workspace = await _selectMainWorkspace(controller, harness);
        final firstGroupId = controller.state
            .layoutFor(workspace.id)!
            .activeGroupId;
        final movedTab = await controller.splitWorkbenchGroupWithTerminal(
          workspace: workspace,
          groupId: firstGroupId,
          zone: WorkbenchDropZone.down,
        );
        await _flush();
        final splitLayout = controller.state.layoutFor(workspace.id)!;
        expect(splitLayout.paneGroupIds, hasLength(2));

        await controller.moveWorkspaceTab(
          workspaceId: workspace.id,
          tabId: movedTab.id,
          targetGroupId: firstGroupId,
          zone: WorkbenchDropZone.center,
        );
        await _flush();

        final layout = controller.state.layoutFor(workspace.id)!;
        expect(layout.paneGroupIds, <String>[firstGroupId]);
        expect(layout.groups[firstGroupId]?.tabIds, contains(movedTab.id));
        expect(controller.state.activeWorkspaceTab?.id, movedTab.id);
      },
    );

    test('updates and persists split ratios', () async {
      await controller.bootstrap();
      final workspace = await _selectMainWorkspace(controller, harness);
      final groupId = controller.state.layoutFor(workspace.id)!.activeGroupId;
      await controller.splitWorkbenchGroupWithTerminal(
        workspace: workspace,
        groupId: groupId,
        zone: WorkbenchDropZone.right,
      );
      await _flush();

      controller.updateWorkbenchSplitRatio(
        workspaceId: workspace.id,
        nodePath: const <int>[],
        ratio: 0.8,
      );
      await _flush();

      final layout = controller.state.layoutFor(workspace.id)!;
      expect(layout.root.ratio, 0.8);
      expect(
        await harness.workbenchRepository.findWorkbenchLayout(workspace.id),
        isNotNull,
      );
      expect(
        (await harness.workbenchRepository.findWorkbenchLayout(
          workspace.id,
        ))!.root.ratio,
        0.8,
      );
    });

    test('selecting a workspace preserves the saved active tab', () async {
      final workspace = Workspace(
        id: 'workspace-1',
        projectId: harness.project.id,
        name: 'Main',
        branch: 'main',
        path: harness.project.repoPath,
        createdAt: DateTime.utc(2026, 5, 22),
        updatedAt: DateTime.utc(2026, 5, 22),
        kind: WorkspaceKind.main,
        status: WorkspaceStatus.active,
      );
      final firstTab = WorkspaceTabRecord(
        id: 'tab-1',
        workspaceId: workspace.id,
        title: 'Terminal 1',
        createdAt: DateTime.utc(2026, 5, 22),
        updatedAt: DateTime.utc(2026, 5, 22),
      );
      final secondTab = WorkspaceTabRecord(
        id: 'tab-2',
        workspaceId: workspace.id,
        title: 'Terminal 2',
        createdAt: DateTime.utc(2026, 5, 22),
        updatedAt: DateTime.utc(2026, 5, 22),
      );
      final savedLayout =
          WorkbenchLayout.single(
            workspaceId: workspace.id,
            tabIds: <String>[firstTab.id],
          ).splitWithGroup(
            targetGroupId: WorkbenchLayout.defaultGroupId(workspace.id),
            zone: WorkbenchDropZone.right,
            newGroup: WorkbenchPaneGroup(
              id: 'group-2',
              tabIds: <String>[secondTab.id],
              activeTabId: secondTab.id,
            ),
          );
      await harness.workbenchRepository.upsertWorkspace(workspace);
      await harness.workbenchRepository.upsertWorkspaceTab(firstTab);
      await harness.workbenchRepository.upsertWorkspaceTab(secondTab);
      await harness.workbenchRepository.upsertWorkbenchLayout(savedLayout);

      await controller.selectWorkspace(
        project: harness.project,
        workspace: workspace,
      );
      await _flush();

      expect(
        controller.state.layoutFor(workspace.id)?.activeTabId,
        secondTab.id,
      );
      expect(
        controller.state.activeTabIdByWorkspace[workspace.id],
        secondTab.id,
      );
      expect(
        harness.workbenchRepository
            .peekWorkbenchLayout(workspace.id)
            ?.activeTabId,
        secondTab.id,
      );
    });

    test(
      'tab watcher does not overwrite a saved split before layout load finishes',
      () async {
        final workspace = Workspace(
          id: 'workspace-1',
          projectId: harness.project.id,
          name: 'Main',
          branch: 'main',
          path: harness.project.repoPath,
          createdAt: DateTime.utc(2026, 5, 22),
          updatedAt: DateTime.utc(2026, 5, 22),
          kind: WorkspaceKind.main,
          status: WorkspaceStatus.active,
        );
        final firstTab = WorkspaceTabRecord(
          id: 'tab-1',
          workspaceId: workspace.id,
          title: 'Terminal 1',
          createdAt: DateTime.utc(2026, 5, 22),
          updatedAt: DateTime.utc(2026, 5, 22),
        );
        final secondTab = WorkspaceTabRecord(
          id: 'tab-2',
          workspaceId: workspace.id,
          title: 'Terminal 2',
          createdAt: DateTime.utc(2026, 5, 22),
          updatedAt: DateTime.utc(2026, 5, 22),
        );
        final savedLayout =
            WorkbenchLayout.single(
              workspaceId: workspace.id,
              tabIds: <String>[firstTab.id],
            ).splitWithGroup(
              targetGroupId: WorkbenchLayout.defaultGroupId(workspace.id),
              zone: WorkbenchDropZone.right,
              newGroup: WorkbenchPaneGroup(
                id: 'group-2',
                tabIds: <String>[secondTab.id],
                activeTabId: secondTab.id,
              ),
            );
        final layoutRead = Completer<WorkbenchLayout?>();
        harness.workbenchRepository.blockFindWorkbenchLayoutWith(
          layoutRead.future,
        );
        await harness.workbenchRepository.upsertWorkspace(workspace);
        await harness.workbenchRepository.upsertWorkspaceTab(firstTab);
        await harness.workbenchRepository.upsertWorkspaceTab(secondTab);
        await harness.workbenchRepository.upsertWorkbenchLayout(savedLayout);

        await controller.bootstrap();
        await _flushUntil(
          () => harness.workbenchRepository.hasTabWatcher(workspace.id),
        );

        harness.workbenchRepository.emitTabs(workspace.id);
        await _flush();

        expect(
          harness.workbenchRepository
              .peekWorkbenchLayout(workspace.id)
              ?.root
              .axis,
          WorkbenchSplitAxis.horizontal,
        );
        expect(controller.state.layoutFor(workspace.id), isNull);

        layoutRead.complete(savedLayout);
        await _flushUntil(
          () => controller.state.layoutFor(workspace.id) != null,
        );

        final persisted = harness.workbenchRepository.peekWorkbenchLayout(
          workspace.id,
        );
        expect(persisted?.root.axis, WorkbenchSplitAxis.horizontal);
        expect(persisted?.paneGroupIds, hasLength(2));
        expect(
          controller.state.layoutFor(workspace.id)?.paneGroupIds,
          hasLength(2),
        );
      },
    );

    test('bootstrap ignores persisted view-prefs load failures', () async {
      harness.viewPrefsRepository.loadError = Exception('bad prefs');

      await controller.bootstrap();
      await _flushUntil(
        () => controller.state.workspacesFor(harness.project.id).isNotEmpty,
      );

      expect(controller.state.bootstrapped, isTrue);
      expect(controller.state.viewPrefs, WorkbenchViewPrefs.defaults);
      expect(controller.state.error, isNull);
    });

    test('view-pref mutators update state and persist changes', () async {
      await controller.bootstrap();
      final mainWorkspace = await _selectMainWorkspace(controller, harness);
      final linkedWorkspace = await controller.createWorkspace(
        project: harness.project,
        sourceBranch: 'main',
        newBranchName: 'feature/view-prefs',
      );
      await _flush();

      controller.toggleCollapseAll();
      expect(
        controller.state.viewPrefs.collapsedProjectIds,
        contains(harness.project.id),
      );

      controller.toggleCollapseAll();
      expect(
        controller.state.viewPrefs.collapsedProjectIds,
        isNot(contains(harness.project.id)),
      );

      controller.setGroupBy(WorkbenchGroupBy.none);
      controller.setWorkspaceExpanded(mainWorkspace.id, false);
      controller.setWorkspaceExpanded(linkedWorkspace.id, false);
      controller.setProjectSort(WorkbenchSortBy.recent);
      controller.setWorkspaceSort(WorkbenchSortBy.recent);
      controller.toggleCollapseAll();
      expect(
        controller.state.viewPrefs.expandedWorkspaceIds,
        containsAll(<String>[mainWorkspace.id, linkedWorkspace.id]),
      );

      controller.toggleCollapseAll();
      controller.toggleWorkspaceExpanded(mainWorkspace.id);
      controller.setWorkspaceExpanded(mainWorkspace.id, false);
      controller.addProjectFilter(harness.project.id);
      controller.toggleProjectFilter(harness.project.id);
      controller.clearProjectFilters();
      controller.setSearchQuery('terminal');
      controller.setCollapsed(true);
      controller.setSidebarWidth(AleraTokens.sidebarMaxWidth + 400);
      await _flush();

      expect(controller.state.viewPrefs.groupBy, WorkbenchGroupBy.none);
      expect(controller.state.viewPrefs.projectSort, WorkbenchSortBy.recent);
      expect(controller.state.viewPrefs.workspaceSort, WorkbenchSortBy.recent);
      expect(controller.state.viewPrefs.selectedProjectIds, isEmpty);
      expect(
        controller.state.viewPrefs.expandedWorkspaceIds,
        isNot(contains(mainWorkspace.id)),
      );
      expect(controller.state.searchQuery, 'terminal');
      expect(controller.state.collapsed, isTrue);
      expect(controller.state.sidebarWidth, AleraTokens.sidebarMaxWidth);
      expect(
        harness.viewPrefsRepository.prefs.workspaceSort,
        WorkbenchSortBy.recent,
      );
      expect(harness.viewPrefsRepository.saveCount, greaterThan(0));
    });

    test('bootstrap prunes stale persisted project filters', () async {
      harness.viewPrefsRepository.prefs = WorkbenchViewPrefs.defaults.copyWith(
        collapsedProjectIds: <String>{'stale-project', harness.project.id},
        selectedProjectIds: <String>{'stale-project', harness.project.id},
      );

      await controller.bootstrap();
      await _flushUntil(
        () => controller.state.workspacesFor(harness.project.id).isNotEmpty,
      );

      expect(controller.state.viewPrefs.collapsedProjectIds, <String>{
        harness.project.id,
      });
      expect(controller.state.viewPrefs.selectedProjectIds, <String>{
        harness.project.id,
      });
    });

    test('bootstrap surfaces project repository failures', () async {
      harness.projectRepository.listAllError = StateError('cannot list projects');

      await controller.bootstrap();
      await _flush();

      expect(controller.state.bootstrapped, isTrue);
      expect(
        controller.state.error,
        contains('Failed to bootstrap workbench: Bad state: cannot list projects'),
      );
    });

    test(
      'workspace updates prune expansion ids for removed workspaces',
      () async {
        await controller.bootstrap();
        await _selectMainWorkspace(controller, harness);
        final linkedWorkspace = await controller.createWorkspace(
          project: harness.project,
          sourceBranch: 'main',
          newBranchName: 'feature/remove-expanded',
        );
        await _flush();

        expect(
          controller.state.viewPrefs.expandedWorkspaceIds,
          contains(linkedWorkspace.id),
        );

        await harness.workbenchRepository.removeWorkspace(linkedWorkspace.id);
        await _flush();

        expect(
          controller.state.viewPrefs.expandedWorkspaceIds,
          isNot(contains(linkedWorkspace.id)),
        );
      },
    );

    test('surfaces project and workspace action failures in state', () async {
      await expectLater(controller.addLocalProject(path: ''), throwsStateError);
      expect(
        controller.state.error,
        contains('Project path must not be empty'),
      );

      await expectLater(
        controller.cloneProject(
          gitUrl: 'https://example.com/repo.git',
          destinationPath: '',
        ),
        throwsStateError,
      );
      expect(
        controller.state.error,
        contains('Destination path must not be empty'),
      );

      await expectLater(
        controller.renameProject(projectId: 'missing', name: 'Renamed'),
        throwsStateError,
      );
      expect(controller.state.error, contains('project not found'));

      harness.projectRepository.removeError = StateError('cannot remove');
      await expectLater(
        controller.removeProject(harness.project.id),
        throwsStateError,
      );
      expect(controller.state.error, contains('cannot remove'));

      await expectLater(
        controller.createWorkspace(
          project: harness.project,
          sourceBranch: '',
          newBranchName: 'feature/failure',
        ),
        throwsA(isA<WorkspaceException>()),
      );
      expect(controller.state.error, contains('Source branch is required'));

      await expectLater(
        controller.renameWorkspace(workspaceId: 'missing', name: 'Renamed'),
        throwsA(isA<WorkspaceException>()),
      );
      expect(controller.state.error, contains('Workspace not found'));

      await controller.bootstrap();
      final mainWorkspace = await _selectMainWorkspace(controller, harness);

      await expectLater(
        controller.deleteWorkspace(
          project: harness.project,
          workspace: mainWorkspace,
        ),
        throwsA(isA<WorkspaceException>()),
      );
      expect(
        controller.state.error,
        contains('The main workspace cannot be removed'),
      );
    });

    test('surfaces tab and layout failures in state', () async {
      await controller.bootstrap();
      final workspace = await _selectMainWorkspace(controller, harness);
      final activeTab = controller.state.activeWorkspaceTab!;

      harness.workbenchRepository.upsertWorkspaceTabError = StateError(
        'cannot create tab',
      );
      await expectLater(
        controller.createTerminalTab(workspace),
        throwsStateError,
      );
      expect(controller.state.error, contains('cannot create tab'));
      harness.workbenchRepository.upsertWorkspaceTabError = null;

      harness.workbenchRepository.removeWorkspaceTabError = StateError(
        'cannot close tab',
      );
      await expectLater(
        controller.closeWorkspaceTabs(
          workspace: workspace,
          tabIds: <String>[activeTab.id],
        ),
        throwsStateError,
      );
      expect(controller.state.error, contains('cannot close tab'));
      harness.workbenchRepository.removeWorkspaceTabError = null;

      await expectLater(
        controller.renameWorkspaceTab(tabId: activeTab.id, title: '   '),
        throwsStateError,
      );
      expect(
        controller.state.error,
        contains('Terminal title must not be empty'),
      );

      final firstGroupId = controller.state
          .layoutFor(workspace.id)!
          .activeGroupId;
      final splitTab = await controller.splitWorkbenchGroupWithTerminal(
        workspace: workspace,
        groupId: firstGroupId,
        zone: WorkbenchDropZone.right,
      );
      await _flush();

      final splitLayout = controller.state.layoutFor(workspace.id)!;
      final splitGroupId = splitLayout.groupIdForTab(splitTab.id)!;
      final targetGroupId = splitLayout.paneGroupIds.firstWhere(
        (groupId) => groupId != splitGroupId,
      );

      harness.workbenchRepository.upsertWorkbenchLayoutError = StateError(
        'cannot persist layout',
      );
      await expectLater(
        controller.moveWorkspaceTab(
          workspaceId: workspace.id,
          tabId: splitTab.id,
          targetGroupId: targetGroupId,
          zone: WorkbenchDropZone.center,
        ),
        throwsStateError,
      );
      expect(controller.state.error, contains('cannot persist layout'));

      await expectLater(
        controller.mergeWorkbenchGroupIntoSibling(
          workspaceId: workspace.id,
          groupId: splitGroupId,
        ),
        throwsStateError,
      );
      expect(controller.state.error, contains('cannot persist layout'));
      harness.workbenchRepository.upsertWorkbenchLayoutError = null;

      await controller.mergeWorkbenchGroupIntoSibling(
        workspaceId: workspace.id,
        groupId: splitGroupId,
      );
      await _flush();
      expect(controller.state.error, isNull);

      harness.workbenchRepository.upsertWorkspaceTabError = StateError(
        'cannot split tab',
      );
      await expectLater(
        controller.splitWorkbenchGroupWithTerminal(
          workspace: workspace,
          groupId: targetGroupId,
          zone: WorkbenchDropZone.down,
        ),
        throwsStateError,
      );
      expect(controller.state.error, contains('cannot split tab'));
    });

    test(
      'activates projects and tabs without unnecessary state changes',
      () async {
        await controller.bootstrap();
        final workspace = await _selectMainWorkspace(controller, harness);
        final firstTab = controller.state.activeWorkspaceTab!;
        final secondTab = await controller.createTerminalTab(workspace);
        await _flush();

        final beforeNoOpClose = controller.state;
        await controller.closeWorkspaceTabs(
          workspace: workspace,
          tabIds: const [],
        );
        expect(controller.state, same(beforeNoOpClose));

        await controller.activateProject(harness.project);
        expect(controller.state.activeProjectId, harness.project.id);
        expect(controller.state.activeWorkspace, isNull);

        await controller.selectWorkspace(
          project: harness.project,
          workspace: workspace,
        );
        await _flush();

        controller.setActiveTab(workspaceId: workspace.id, tabId: firstTab.id);
        expect(controller.state.activeWorkspaceId, workspace.id);
        expect(controller.state.activeTabIdByWorkspace[workspace.id], firstTab.id);
        expect(controller.state.layoutFor(workspace.id)?.activeTabId, firstTab.id);

        final groupId = controller.state
            .layoutFor(workspace.id)!
            .groupIdForTab(secondTab.id)!;
        controller.setActiveWorkspaceTab(
          workspaceId: workspace.id,
          groupId: groupId,
          tabId: secondTab.id,
        );
        expect(controller.state.activeWorkspaceId, workspace.id);
        expect(
          controller.state.activeTabIdByWorkspace[workspace.id],
          secondTab.id,
        );
        expect(
          controller.state.layoutFor(workspace.id)?.activeTabId,
          secondTab.id,
        );
        expect(
          controller.state.layoutFor(workspace.id)?.activeGroupId,
          groupId,
        );
      },
    );

    test('view-pref no-op mutators avoid redundant persistence', () async {
      await controller.bootstrap();

      final initialSaveCount = harness.viewPrefsRepository.saveCount;
      controller.setGroupBy(controller.state.viewPrefs.groupBy);
      controller.setProjectSort(controller.state.viewPrefs.projectSort);
      controller.setWorkspaceSort(controller.state.viewPrefs.workspaceSort);
      controller.removeProjectFilter('missing-project');
      controller.clearProjectFilters();
      await _flush();
      expect(harness.viewPrefsRepository.saveCount, initialSaveCount);

      controller.addProjectFilter(harness.project.id);
      await _flush();
      final afterAddFilter = harness.viewPrefsRepository.saveCount;

      controller.addProjectFilter(harness.project.id);
      await _flush();
      expect(harness.viewPrefsRepository.saveCount, afterAddFilter);

      controller.clearProjectFilters();
      await _flush();
      final afterClear = harness.viewPrefsRepository.saveCount;

      controller.clearProjectFilters();
      await _flush();
      expect(harness.viewPrefsRepository.saveCount, afterClear);
    });

    test('addProject and cloneProject activate newly added projects', () async {
      await controller.bootstrap();

      final localRepoPath = p.join(harness.tempDir.path, 'repo-added');
      Directory(localRepoPath).createSync(recursive: true);
      Directory(p.join(localRepoPath, '.git')).createSync();

      final localProject = await controller.addProject(
        repoPath: localRepoPath,
        name: 'Added repo',
      );
      await _flushUntil(
        () => controller.state.projects.any((project) => project.id == localProject.id),
      );
      await _flushUntil(
        () => controller.state.workspacesFor(localProject.id).isNotEmpty,
      );

      expect(controller.state.activeProjectId, localProject.id);
      expect(controller.state.workspacesFor(localProject.id).single.isMain, isTrue);

      harness.processRunner.createGitClone = true;
      final cloneDestination = p.join(harness.tempDir.path, 'repo-cloned');
      final clonedProject = await controller.cloneProject(
        gitUrl: 'https://example.com/acme/alera.git',
        destinationPath: cloneDestination,
        name: 'Cloned repo',
      );
      await _flushUntil(
        () => controller.state.projects.any((project) => project.id == clonedProject.id),
      );
      await _flushUntil(
        () => controller.state.workspacesFor(clonedProject.id).isNotEmpty,
      );

      expect(controller.state.activeProjectId, clonedProject.id);
      expect(controller.state.workspacesFor(clonedProject.id).single.isMain, isTrue);
    });

    test('project and workspace toggle helpers cover removal branches', () async {
      await controller.bootstrap();
      final workspace = await _selectMainWorkspace(controller, harness);

      controller.toggleProjectCollapsed(harness.project.id);
      expect(
        controller.state.viewPrefs.collapsedProjectIds,
        contains(harness.project.id),
      );
      controller.toggleProjectCollapsed(harness.project.id);
      expect(
        controller.state.viewPrefs.collapsedProjectIds,
        isNot(contains(harness.project.id)),
      );

      controller.toggleProjectFilter(harness.project.id);
      expect(
        controller.state.viewPrefs.selectedProjectIds,
        contains(harness.project.id),
      );
      controller.removeProjectFilter(harness.project.id);
      expect(controller.state.viewPrefs.selectedProjectIds, isEmpty);

      controller.setWorkspaceExpanded(workspace.id, false);
      expect(
        controller.state.viewPrefs.expandedWorkspaceIds,
        isNot(contains(workspace.id)),
      );
      controller.setWorkspaceExpanded(workspace.id, true);
      expect(
        controller.state.viewPrefs.expandedWorkspaceIds,
        contains(workspace.id),
      );
      controller.toggleWorkspaceExpanded(workspace.id);
      expect(
        controller.state.viewPrefs.expandedWorkspaceIds,
        isNot(contains(workspace.id)),
      );
    });

    test('removing a project prunes its workspaces, tabs, and selections', () async {
      await controller.bootstrap();
      final secondProject = await harness.addProject('project-2', 'Beta');
      await _flushUntil(
        () => controller.state.workspacesFor(secondProject.id).isNotEmpty,
      );

      final secondWorkspace = controller.state.workspacesFor(secondProject.id).single;
      await controller.selectWorkspace(
        project: secondProject,
        workspace: secondWorkspace,
      );
      await _flush();

      expect(controller.state.tabsFor(secondWorkspace.id), isNotEmpty);
      expect(
        controller.state.activeTabIdByWorkspace.containsKey(secondWorkspace.id),
        isTrue,
      );

      await controller.removeProject(secondProject.id);
      await _flush();

      expect(
        controller.state.projects.map((project) => project.id),
        isNot(contains(secondProject.id)),
      );
      expect(
        controller.state.workspacesByProject.containsKey(secondProject.id),
        isFalse,
      );
      expect(
        controller.state.tabsByWorkspace.containsKey(secondWorkspace.id),
        isFalse,
      );
      expect(
        controller.state.activeTabIdByWorkspace.containsKey(secondWorkspace.id),
        isFalse,
      );
      expect(controller.state.error, isNull);
    });

    test('bootstrap surfaces workspace preparation failures', () async {
      harness.workbenchRepository.upsertWorkspaceError = StateError(
        'cannot prepare workspace',
      );

      await controller.bootstrap();
      await _flush();

      expect(
        controller.state.error,
        contains('Failed to prepare workspace for "Alera"'),
      );
    });

    test('reactivating an existing project clears stale collapsed prefs', () async {
      await controller.bootstrap();
      final secondProject = await harness.addProject('project-2', 'Beta');
      await _flushUntil(
        () => controller.state.projects.any((project) => project.id == secondProject.id),
      );

      controller.state = controller.state.copyWith(
        viewPrefs: controller.state.viewPrefs.copyWith(
          collapsedProjectIds: <String>{secondProject.id},
        ),
      );

      final project = await controller.addProject(repoPath: secondProject.repoPath);
      await _flush();

      expect(project.id, secondProject.id);
      expect(
        controller.state.viewPrefs.collapsedProjectIds,
        isNot(contains(secondProject.id)),
      );
      expect(
        harness.viewPrefsRepository.prefs.collapsedProjectIds,
        isNot(contains(secondProject.id)),
      );
    });

    test('workspace watchers recover invalid selections and surface layout load failures', () async {
      await controller.bootstrap();
      final workspace = await _selectMainWorkspace(controller, harness);
      final secondProject = await harness.addProject('project-2', 'Beta');
      await _flushUntil(
        () => controller.state.workspacesFor(secondProject.id).isNotEmpty,
      );
      final secondWorkspace = controller.state.workspacesFor(secondProject.id).single;

      controller.state = controller.state.copyWith(
        activeProjectId: 'missing-project',
        activeWorkspaceId: secondWorkspace.id,
      );
      await harness.workbenchRepository.upsertWorkspace(
        secondWorkspace.copyWith(updatedAt: DateTime.utc(2026, 5, 23)),
      );
      await _flush();

      expect(controller.state.activeProjectId, secondProject.id);

      controller.state = controller.state.copyWith(
        activeProjectId: null,
        activeWorkspaceId: secondWorkspace.id,
      );
      await harness.workbenchRepository.upsertWorkspace(
        secondWorkspace.copyWith(updatedAt: DateTime.utc(2026, 5, 24)),
      );
      await _flush();

      expect(controller.state.activeWorkspaceId, secondWorkspace.id);

      controller.state = controller.state.copyWith(
        activeProjectId: workspace.projectId,
        activeWorkspaceId: workspace.id,
        layoutByWorkspace: <String, WorkbenchLayout>{},
      );
      harness.workbenchRepository.upsertWorkbenchLayoutError = StateError(
        'bad layout',
      );
      harness.workbenchRepository.emitTabs(workspace.id);
      await _flushUntil(() => controller.state.error != null);
      harness.workbenchRepository.upsertWorkbenchLayoutError = null;

      expect(controller.state.error, contains('bad layout'));
      expect(controller.state.activeWorkspaceId, workspace.id);
    });

    test('tab operations fall back when no layout exists', () async {
      await controller.bootstrap();
      final workspace = await _selectMainWorkspace(controller, harness);
      final existingTab = controller.state.activeWorkspaceTab!;

      controller.state = controller.state.copyWith(
        layoutByWorkspace: <String, WorkbenchLayout>{},
        activeTabIdByWorkspace: <String, String>{},
      );

      controller.setActiveTab(workspaceId: workspace.id, tabId: existingTab.id);
      await _flush();

      expect(
        controller.state.activeTabIdByWorkspace[workspace.id],
        existingTab.id,
      );

      final newTab = await controller.createTerminalTab(workspace);
      await _flush();

      expect(controller.state.tabsFor(workspace.id), contains(newTab));
      expect(controller.state.layoutFor(workspace.id), isNotNull);
    });
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

Future<Workspace> _selectMainWorkspace(
  WorkbenchController controller,
  _WorkbenchHarness harness,
) async {
  await _flushUntil(
    () => controller.state.workspacesFor(harness.project.id).isNotEmpty,
  );
  final workspace = controller.state.workspacesFor(harness.project.id).single;
  await controller.selectWorkspace(
    project: harness.project,
    workspace: workspace,
  );
  await _flush();
  return workspace;
}

Future<void> _flushUntil(bool Function() condition, {int attempts = 20}) async {
  for (var i = 0; i < attempts; i += 1) {
    if (condition()) {
      return;
    }
    await _flush();
  }
  throw StateError('condition was not met');
}

class _WorkbenchHarness {
  _WorkbenchHarness() {
    tempDir = Directory.systemTemp.createTempSync(
      'alera-workbench-controller-',
    );
    final repoPath = p.join(tempDir.path, 'repo');
    Directory(repoPath).createSync(recursive: true);
    project = Project(
      id: 'project-1',
      name: 'Alera',
      repoPath: repoPath,
      createdAt: DateTime.utc(2026, 5, 22),
      updatedAt: DateTime.utc(2026, 5, 22),
    );
    projectRepository = _FakeProjectRepository(<Project>[project]);
    workbenchRepository = _FakeWorkbenchRepository();
    processRunner = _FakeProcessRunner();
    viewPrefsRepository = _FakeWorkbenchViewPrefsRepository();
    final projectService = ProjectService(processRunner);
    final projectsService = ProjectsService(
      projectService: projectService,
      projectRepository: projectRepository,
    );
    final workspaceTabService = WorkspaceTabService(
      repository: workbenchRepository,
      now: () => DateTime.utc(2026, 5, 22, 1),
    );
    final settings = AleraSettings.defaults.copyWith(
      general: AleraSettings.defaults.general.copyWith(
        workspaceDirectory: p.join(tempDir.path, 'workspaces'),
      ),
    );
    container = ProviderContainer(
      overrides: [
        processRunnerProvider.overrideWithValue(processRunner),
        projectRepositoryProvider.overrideWithValue(projectRepository),
        workbenchRepositoryProvider.overrideWithValue(workbenchRepository),
        projectServiceProvider.overrideWithValue(projectService),
        projectsServiceProvider.overrideWithValue(projectsService),
        workspaceTabServiceProvider.overrideWithValue(workspaceTabService),
        workbenchViewPrefsRepositoryProvider.overrideWithValue(
          viewPrefsRepository,
        ),
        settingsControllerProvider.overrideWithValue(settings),
      ],
    );
    controller = container.read(workbenchControllerProvider.notifier);
  }

  late final Directory tempDir;
  late final Project project;
  late final _FakeProjectRepository projectRepository;
  late final _FakeWorkbenchRepository workbenchRepository;
  late final _FakeProcessRunner processRunner;
  late final _FakeWorkbenchViewPrefsRepository viewPrefsRepository;
  late final ProviderContainer container;
  late final WorkbenchController controller;

  Future<Project> addProject(String id, String name) async {
    final repoPath = p.join(tempDir.path, id);
    Directory(repoPath).createSync(recursive: true);
    final newProject = Project(
      id: id,
      name: name,
      repoPath: repoPath,
      createdAt: DateTime.utc(2026, 5, 22),
      updatedAt: DateTime.utc(2026, 5, 22),
    );
    await projectRepository.add(newProject);
    return newProject;
  }

  Future<void> dispose() async {
    container.dispose();
    await projectRepository.dispose();
    await workbenchRepository.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}

class _FakeWorkbenchViewPrefsRepository
    implements WorkbenchViewPrefsRepository {
  WorkbenchViewPrefs prefs = WorkbenchViewPrefs.defaults;
  Object? loadError;
  Object? saveError;
  int saveCount = 0;

  @override
  Future<WorkbenchViewPrefs> load() async {
    if (loadError case final Object error) {
      throw error;
    }
    return prefs;
  }

  @override
  Future<void> save(WorkbenchViewPrefs prefs) async {
    saveCount += 1;
    if (saveError case final Object error) {
      throw error;
    }
    this.prefs = prefs;
  }
}

class _FakeProjectRepository implements ProjectRepository {
  _FakeProjectRepository(this._projects);

  final List<Project> _projects;
  final StreamController<List<Project>> _projectsController =
      StreamController<List<Project>>.broadcast();
  Object? listAllError;
  Object? addError;
  Object? updateError;
  Object? removeError;

  @override
  Future<List<Project>> listAll() async {
    if (listAllError case final Object error) {
      throw error;
    }
    return List<Project>.from(_projects);
  }

  @override
  Stream<List<Project>> watchAll() => _projectsController.stream;

  Future<void> dispose() => _projectsController.close();

  @override
  Future<Project> add(Project project) async {
    if (addError case final Object error) {
      throw error;
    }
    _projects.add(project);
    _projectsController.add(List<Project>.from(_projects));
    return project;
  }

  @override
  Future<Project> update(Project project) async {
    if (updateError case final Object error) {
      throw error;
    }
    final index = _projects.indexWhere((entry) => entry.id == project.id);
    if (index == -1) {
      _projects.add(project);
    } else {
      _projects[index] = project;
    }
    _projectsController.add(List<Project>.from(_projects));
    return project;
  }

  @override
  Future<void> remove(String projectId) async {
    if (removeError case final Object error) {
      throw error;
    }
    _projects.removeWhere((project) => project.id == projectId);
    _projectsController.add(List<Project>.from(_projects));
  }
}

class _FakeWorkbenchRepository implements WorkbenchRepository {
  final Map<String, List<Workspace>> _workspacesByProject =
      <String, List<Workspace>>{};
  final Map<String, List<WorkspaceTabRecord>> _tabsByWorkspace =
      <String, List<WorkspaceTabRecord>>{};
  final Map<String, WorkbenchLayout> _layoutsByWorkspace =
      <String, WorkbenchLayout>{};
  final Map<String, StreamController<List<Workspace>>> _workspaceControllers =
      <String, StreamController<List<Workspace>>>{};
  final Map<String, StreamController<List<WorkspaceTabRecord>>>
  _tabControllers = <String, StreamController<List<WorkspaceTabRecord>>>{};
  Future<WorkbenchLayout?>? _findWorkbenchLayoutOverride;
  Object? upsertWorkspaceError;
  Object? upsertWorkspaceTabError;
  Object? upsertWorkbenchLayoutError;
  Object? removeWorkspaceTabError;

  @override
  Future<List<Workspace>> listWorkspaces(String projectId) async {
    return List<Workspace>.from(
      _workspacesByProject[projectId] ?? const <Workspace>[],
    );
  }

  @override
  Stream<List<Workspace>> watchWorkspaces(String projectId) {
    return _workspaceControllers
        .putIfAbsent(
          projectId,
          () => StreamController<List<Workspace>>.broadcast(),
        )
        .stream;
  }

  @override
  Future<Workspace?> findWorkspaceById(String workspaceId) async {
    for (final workspaces in _workspacesByProject.values) {
      for (final workspace in workspaces) {
        if (workspace.id == workspaceId) {
          return workspace;
        }
      }
    }
    return null;
  }

  @override
  Future<Workspace> upsertWorkspace(Workspace workspace) async {
    if (upsertWorkspaceError case final Object error) {
      throw error;
    }
    final current = List<Workspace>.from(
      _workspacesByProject[workspace.projectId] ?? const <Workspace>[],
    );
    final index = current.indexWhere((entry) => entry.id == workspace.id);
    if (index == -1) {
      current.add(workspace);
    } else {
      current[index] = workspace;
    }
    current.sort((left, right) {
      if (left.isMain != right.isMain) {
        return left.isMain ? -1 : 1;
      }
      return left.createdAt.compareTo(right.createdAt);
    });
    _workspacesByProject[workspace.projectId] = current;
    _workspaceControllers[workspace.projectId]?.add(
      List<Workspace>.from(current),
    );
    return workspace;
  }

  @override
  Future<void> removeWorkspace(
    String workspaceId, {
    bool cascadeTabs = true,
  }) async {
    String? projectId;
    for (final entry in _workspacesByProject.entries) {
      if (entry.value.any((workspace) => workspace.id == workspaceId)) {
        projectId = entry.key;
        entry.value.removeWhere((workspace) => workspace.id == workspaceId);
        break;
      }
    }
    if (projectId != null) {
      _workspaceControllers[projectId]?.add(
        List<Workspace>.from(
          _workspacesByProject[projectId] ?? const <Workspace>[],
        ),
      );
    }
    if (cascadeTabs) {
      await removeWorkspaceTabsForWorkspace(workspaceId);
    }
    await removeWorkbenchLayout(workspaceId);
  }

  @override
  Future<void> removeWorkspacesForProject(String projectId) async {
    final workspaces =
        _workspacesByProject.remove(projectId) ?? const <Workspace>[];
    _workspaceControllers[projectId]?.add(const <Workspace>[]);
    for (final workspace in workspaces) {
      await removeWorkspaceTabsForWorkspace(workspace.id);
      await removeWorkbenchLayout(workspace.id);
    }
  }

  @override
  Future<List<WorkspaceTabRecord>> listWorkspaceTabs(String workspaceId) async {
    return List<WorkspaceTabRecord>.from(
      _tabsByWorkspace[workspaceId] ?? const <WorkspaceTabRecord>[],
    );
  }

  @override
  Stream<List<WorkspaceTabRecord>> watchWorkspaceTabs(String workspaceId) {
    return _tabControllers
        .putIfAbsent(
          workspaceId,
          () => StreamController<List<WorkspaceTabRecord>>.broadcast(),
        )
        .stream;
  }

  @override
  Future<WorkspaceTabRecord?> findWorkspaceTabById(String tabId) async {
    for (final tabs in _tabsByWorkspace.values) {
      for (final tab in tabs) {
        if (tab.id == tabId) {
          return tab;
        }
      }
    }
    return null;
  }

  @override
  Future<WorkbenchLayout?> findWorkbenchLayout(String workspaceId) async {
    final override = _findWorkbenchLayoutOverride;
    if (override != null) {
      return override;
    }
    return _layoutsByWorkspace[workspaceId];
  }

  @override
  Future<WorkspaceTabRecord> upsertWorkspaceTab(WorkspaceTabRecord tab) async {
    if (upsertWorkspaceTabError case final Object error) {
      throw error;
    }
    final current = List<WorkspaceTabRecord>.from(
      _tabsByWorkspace[tab.workspaceId] ?? const <WorkspaceTabRecord>[],
    );
    final index = current.indexWhere((entry) => entry.id == tab.id);
    if (index == -1) {
      current.add(tab);
    } else {
      current[index] = tab;
    }
    current.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    _tabsByWorkspace[tab.workspaceId] = current;
    _tabControllers[tab.workspaceId]?.add(
      List<WorkspaceTabRecord>.from(current),
    );
    return tab;
  }

  @override
  Future<WorkbenchLayout> upsertWorkbenchLayout(WorkbenchLayout layout) async {
    if (upsertWorkbenchLayoutError case final Object error) {
      throw error;
    }
    _layoutsByWorkspace[layout.workspaceId] = layout;
    return layout;
  }

  void blockFindWorkbenchLayoutWith(Future<WorkbenchLayout?> future) {
    _findWorkbenchLayoutOverride = future;
    future.whenComplete(() {
      if (identical(_findWorkbenchLayoutOverride, future)) {
        _findWorkbenchLayoutOverride = null;
      }
    });
  }

  WorkbenchLayout? peekWorkbenchLayout(String workspaceId) {
    return _layoutsByWorkspace[workspaceId];
  }

  bool hasTabWatcher(String workspaceId) {
    return _tabControllers.containsKey(workspaceId);
  }

  void emitTabs(String workspaceId) {
    _tabControllers[workspaceId]?.add(
      List<WorkspaceTabRecord>.from(
        _tabsByWorkspace[workspaceId] ?? const <WorkspaceTabRecord>[],
      ),
    );
  }

  @override
  Future<void> removeWorkspaceTab(String tabId) async {
    if (removeWorkspaceTabError case final Object error) {
      throw error;
    }
    for (final entry in _tabsByWorkspace.entries) {
      final previousLength = entry.value.length;
      entry.value.removeWhere((tab) => tab.id == tabId);
      if (entry.value.length != previousLength) {
        _tabControllers[entry.key]?.add(
          List<WorkspaceTabRecord>.from(entry.value),
        );
        return;
      }
    }
  }

  @override
  Future<void> removeWorkspaceTabsForWorkspace(String workspaceId) async {
    _tabsByWorkspace.remove(workspaceId);
    _tabControllers[workspaceId]?.add(const <WorkspaceTabRecord>[]);
  }

  @override
  Future<void> removeWorkbenchLayout(String workspaceId) async {
    _layoutsByWorkspace.remove(workspaceId);
  }

  Future<void> dispose() async {
    for (final controller in _workspaceControllers.values) {
      await controller.close();
    }
    for (final controller in _tabControllers.values) {
      await controller.close();
    }
  }
}

class _FakeProcessRunner implements ProcessRunner {
  String currentBranch = 'main';
  bool createGitClone = false;

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    if (arguments.length >= 2 &&
        arguments[0] == 'branch' &&
        arguments[1] == '--show-current') {
      return ProcessRunOutput(
        exitCode: 0,
        stdout: '$currentBranch\n',
        stderr: '',
      );
    }
    if (arguments.contains('for-each-ref')) {
      return const ProcessRunOutput(
        exitCode: 0,
        stdout: 'main\norigin/main\n',
        stderr: '',
      );
    }
    if (arguments.length >= 2 &&
        arguments[0] == 'rev-parse' &&
        arguments.contains('--verify')) {
      // No branch with the requested name exists yet.
      return const ProcessRunOutput(exitCode: 1, stdout: '', stderr: '');
    }
    if (arguments.length >= 3 &&
        arguments[0] == 'worktree' &&
        arguments[1] == 'list') {
      return ProcessRunOutput(
        exitCode: 0,
        stdout:
            'worktree ${workingDirectory ?? ''}\nbranch refs/heads/main\n\n',
        stderr: '',
      );
    }
    if (arguments.isNotEmpty && arguments[0] == 'clone') {
      if (createGitClone && arguments.length >= 4) {
        final destination = arguments.last;
        Directory(p.join(destination, '.git')).createSync(recursive: true);
      }
      return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
    }
    return const ProcessRunOutput(exitCode: 0, stdout: '', stderr: '');
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }
}
