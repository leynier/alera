import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workspace_tab_service.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('WorkbenchController', () {
    late _WorkbenchHarness harness;
    late WorkbenchController controller;

    setUp(() {
      harness = _WorkbenchHarness();
      controller = harness.buildController();
    });

    tearDown(() async {
      controller.dispose();
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
  }

  late final Directory tempDir;
  late final Project project;
  late final _FakeProjectRepository projectRepository;
  late final _FakeWorkbenchRepository workbenchRepository;
  late final _FakeProcessRunner processRunner;

  WorkbenchController buildController() {
    final projectsService = ProjectsService(
      projectService: ProjectService(processRunner),
      projectRepository: projectRepository,
    );
    final workspaceService = WorkspaceService(
      repository: workbenchRepository,
      projectService: ProjectService(processRunner),
      processRunner: processRunner,
      workspaceRoot: WorkspaceRoot(
        override: p.join(tempDir.path, 'workspaces'),
      ),
      now: () => DateTime.utc(2026, 5, 22, 1),
    );
    final workspaceTabService = WorkspaceTabService(
      repository: workbenchRepository,
      now: () => DateTime.utc(2026, 5, 22, 1),
    );
    return WorkbenchController(
      projectsService: projectsService,
      repository: workbenchRepository,
      workspaceService: workspaceService,
      workspaceTabService: workspaceTabService,
    );
  }

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
    await projectRepository.dispose();
    await workbenchRepository.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  }
}

class _FakeProjectRepository implements ProjectRepository {
  _FakeProjectRepository(this._projects);

  final List<Project> _projects;
  final StreamController<List<Project>> _projectsController =
      StreamController<List<Project>>.broadcast();

  @override
  Future<List<Project>> listAll() async => List<Project>.from(_projects);

  @override
  Stream<List<Project>> watchAll() => _projectsController.stream;

  Future<void> dispose() => _projectsController.close();

  @override
  Future<Project> add(Project project) async {
    _projects.add(project);
    _projectsController.add(List<Project>.from(_projects));
    return project;
  }

  @override
  Future<Project> update(Project project) async {
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
