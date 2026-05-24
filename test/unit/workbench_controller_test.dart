import 'dart:async';
import 'dart:io';

import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/terminal_tab_service.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/domain/terminal_tab_record.dart';
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
      'bootstrap selects the main workspace and seeds the first terminal tab',
      () async {
        await controller.bootstrap();
        await _flush();

        expect(controller.state.activeProjectId, harness.project.id);
        expect(controller.state.activeWorkspace, isNotNull);
        expect(controller.state.activeWorkspace!.isMain, isTrue);
        expect(
          controller.state
              .tabsFor(controller.state.activeWorkspace!.id)
              .map((tab) => tab.title),
          <String>['Terminal 1'],
        );
        expect(controller.state.activeTerminalTab?.title, 'Terminal 1');
      },
    );

    test(
      'closing the active tab creates a replacement for the active workspace',
      () async {
        await controller.bootstrap();
        await _flush();

        final workspace = controller.state.activeWorkspace!;
        final firstTab = controller.state.activeTerminalTab!;
        final secondTab = await controller.createTerminalTab(workspace);

        expect(controller.state.activeTerminalTab?.id, secondTab.id);

        await controller.closeTerminalTab(
          workspace: workspace,
          tabId: secondTab.id,
        );
        await _flush();

        expect(controller.state.activeTerminalTab?.id, firstTab.id);

        await controller.closeTerminalTab(
          workspace: workspace,
          tabId: firstTab.id,
        );
        await _flush();

        final tabs = controller.state.tabsFor(workspace.id);
        expect(tabs, hasLength(1));
        expect(controller.state.activeTerminalTab?.id, tabs.single.id);
        expect(controller.state.activeTerminalTab?.title, 'Terminal 1');
      },
    );

    test(
      'deleting a workspace removes it from state without lingering',
      () async {
        await controller.bootstrap();
        await _flush();
        final mainWorkspace = controller.state.activeWorkspace!;

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
      'deleting the active workspace falls back within the same project',
      () async {
        await controller.bootstrap();
        await _flush();
        final mainWorkspace = controller.state.activeWorkspace!;

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
        expect(controller.state.activeWorkspace?.id, mainWorkspace.id);
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
      await _flush();
      final workspace = controller.state.activeWorkspace!;
      final firstTab = controller.state.activeTerminalTab!;
      final groupId = controller.state.layoutFor(workspace.id)!.activeGroupId;

      final secondTab = await controller.splitWorkbenchGroup(
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
      expect(controller.state.activeTerminalTab?.id, secondTab.id);
    });

    test(
      'moves a tab into another stack and collapses the empty source pane',
      () async {
        await controller.bootstrap();
        await _flush();
        final workspace = controller.state.activeWorkspace!;
        final firstGroupId = controller.state
            .layoutFor(workspace.id)!
            .activeGroupId;
        final movedTab = await controller.splitWorkbenchGroup(
          workspace: workspace,
          groupId: firstGroupId,
          zone: WorkbenchDropZone.down,
        );
        await _flush();
        final splitLayout = controller.state.layoutFor(workspace.id)!;
        expect(splitLayout.paneGroupIds, hasLength(2));

        await controller.moveWorkbenchTab(
          workspaceId: workspace.id,
          tabId: movedTab.id,
          targetGroupId: firstGroupId,
          zone: WorkbenchDropZone.center,
        );
        await _flush();

        final layout = controller.state.layoutFor(workspace.id)!;
        expect(layout.paneGroupIds, <String>[firstGroupId]);
        expect(layout.groups[firstGroupId]?.tabIds, contains(movedTab.id));
        expect(controller.state.activeTerminalTab?.id, movedTab.id);
      },
    );

    test('updates and persists split ratios', () async {
      await controller.bootstrap();
      await _flush();
      final workspace = controller.state.activeWorkspace!;
      final groupId = controller.state.layoutFor(workspace.id)!.activeGroupId;
      await controller.splitWorkbenchGroup(
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
      final firstTab = TerminalTabRecord(
        id: 'tab-1',
        workspaceId: workspace.id,
        title: 'Terminal 1',
        createdAt: DateTime.utc(2026, 5, 22),
        updatedAt: DateTime.utc(2026, 5, 22),
      );
      final secondTab = TerminalTabRecord(
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
      await harness.workbenchRepository.upsertWorkbenchTab(firstTab);
      await harness.workbenchRepository.upsertWorkbenchTab(secondTab);
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
        final firstTab = TerminalTabRecord(
          id: 'tab-1',
          workspaceId: workspace.id,
          title: 'Terminal 1',
          createdAt: DateTime.utc(2026, 5, 22),
          updatedAt: DateTime.utc(2026, 5, 22),
        );
        final secondTab = TerminalTabRecord(
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
        await harness.workbenchRepository.upsertWorkbenchTab(firstTab);
        await harness.workbenchRepository.upsertWorkbenchTab(secondTab);
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
    final terminalTabService = TerminalTabService(
      repository: workbenchRepository,
      now: () => DateTime.utc(2026, 5, 22, 1),
    );
    return WorkbenchController(
      projectsService: projectsService,
      repository: workbenchRepository,
      workspaceService: workspaceService,
      terminalTabService: terminalTabService,
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
  Future<Project> update(Project project) async => project;

  @override
  Future<void> remove(String projectId) async {
    _projects.removeWhere((project) => project.id == projectId);
    _projectsController.add(List<Project>.from(_projects));
  }
}

class _FakeWorkbenchRepository implements WorkbenchRepository {
  final Map<String, List<Workspace>> _workspacesByProject =
      <String, List<Workspace>>{};
  final Map<String, List<TerminalTabRecord>> _tabsByWorkspace =
      <String, List<TerminalTabRecord>>{};
  final Map<String, WorkbenchLayout> _layoutsByWorkspace =
      <String, WorkbenchLayout>{};
  final Map<String, StreamController<List<Workspace>>> _workspaceControllers =
      <String, StreamController<List<Workspace>>>{};
  final Map<String, StreamController<List<TerminalTabRecord>>> _tabControllers =
      <String, StreamController<List<TerminalTabRecord>>>{};
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
      await removeTerminalTabsForWorkspace(workspaceId);
    }
    await removeWorkbenchLayout(workspaceId);
  }

  @override
  Future<void> removeWorkspacesForProject(String projectId) async {
    final workspaces =
        _workspacesByProject.remove(projectId) ?? const <Workspace>[];
    _workspaceControllers[projectId]?.add(const <Workspace>[]);
    for (final workspace in workspaces) {
      await removeTerminalTabsForWorkspace(workspace.id);
      await removeWorkbenchLayout(workspace.id);
    }
  }

  @override
  Future<List<TerminalTabRecord>> listTerminalTabs(String workspaceId) async {
    return List<TerminalTabRecord>.from(
      _tabsByWorkspace[workspaceId] ?? const <TerminalTabRecord>[],
    );
  }

  @override
  Future<List<TerminalTabRecord>> listWorkbenchTabs(String workspaceId) {
    return listTerminalTabs(workspaceId);
  }

  @override
  Stream<List<TerminalTabRecord>> watchTerminalTabs(String workspaceId) {
    return _tabControllers
        .putIfAbsent(
          workspaceId,
          () => StreamController<List<TerminalTabRecord>>.broadcast(),
        )
        .stream;
  }

  @override
  Stream<List<TerminalTabRecord>> watchWorkbenchTabs(String workspaceId) {
    return watchTerminalTabs(workspaceId);
  }

  @override
  Future<TerminalTabRecord?> findTerminalTabById(String tabId) async {
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
  Future<TerminalTabRecord?> findWorkbenchTabById(String tabId) {
    return findTerminalTabById(tabId);
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
  Future<TerminalTabRecord> upsertTerminalTab(TerminalTabRecord tab) async {
    final current = List<TerminalTabRecord>.from(
      _tabsByWorkspace[tab.workspaceId] ?? const <TerminalTabRecord>[],
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
      List<TerminalTabRecord>.from(current),
    );
    return tab;
  }

  @override
  Future<TerminalTabRecord> upsertWorkbenchTab(TerminalTabRecord tab) {
    return upsertTerminalTab(tab);
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
      List<TerminalTabRecord>.from(
        _tabsByWorkspace[workspaceId] ?? const <TerminalTabRecord>[],
      ),
    );
  }

  @override
  Future<void> removeTerminalTab(String tabId) async {
    for (final entry in _tabsByWorkspace.entries) {
      final previousLength = entry.value.length;
      entry.value.removeWhere((tab) => tab.id == tabId);
      if (entry.value.length != previousLength) {
        _tabControllers[entry.key]?.add(
          List<TerminalTabRecord>.from(entry.value),
        );
        return;
      }
    }
  }

  @override
  Future<void> removeWorkbenchTab(String tabId) {
    return removeTerminalTab(tabId);
  }

  @override
  Future<void> removeTerminalTabsForWorkspace(String workspaceId) async {
    _tabsByWorkspace.remove(workspaceId);
    _tabControllers[workspaceId]?.add(const <TerminalTabRecord>[]);
  }

  @override
  Future<void> removeWorkbenchTabsForWorkspace(String workspaceId) {
    return removeTerminalTabsForWorkspace(workspaceId);
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
