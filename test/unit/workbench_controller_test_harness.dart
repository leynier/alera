part of 'workbench_controller_test.dart';

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
      'alera-workbench-_controller-',
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
    gitBackend = FakeGitBackend()
      ..sourceBranches = <String>['main', 'origin/main']
      ..includeQueriedRepoAsMain = true;
    viewPrefsRepository = _FakeWorkbenchViewPrefsRepository();
    final projectService = ProjectService(gitBackend);
    final projectsService = ProjectsService(
      projectService: projectService,
      projectRepository: projectRepository,
    );
    final workspaceTabService = WorkspaceTabService(
      repository: workbenchRepository,
      now: () => DateTime.utc(2026, 5, 22, 1),
    );
    worktreeSetupRunner = _FakeWorktreeSetupRunner();
    final settings = AleraSettings.defaults.copyWith(
      general: AleraSettings.defaults.general.copyWith(
        workspaceDirectory: p.join(tempDir.path, 'workspaces'),
      ),
    );
    container = ProviderContainer(
      overrides: [
        gitBackendProvider.overrideWithValue(gitBackend),
        projectRepositoryProvider.overrideWithValue(projectRepository),
        workbenchRepositoryProvider.overrideWithValue(workbenchRepository),
        projectServiceProvider.overrideWithValue(projectService),
        projectConfigServiceProvider.overrideWithValue(
          ProjectConfigService(
            repository: FakeProjectConfigRepository(),
            fileStore: FakeProjectConfigFileStore(),
          ),
        ),
        projectsServiceProvider.overrideWithValue(projectsService),
        workspaceTabServiceProvider.overrideWithValue(workspaceTabService),
        worktreeSetupRunnerProvider.overrideWithValue(worktreeSetupRunner),
        workbenchViewPrefsRepositoryProvider.overrideWithValue(
          viewPrefsRepository,
        ),
        settingsControllerProvider.overrideWithValue(settings),
      ],
    );
    _controller = container.read(workbenchControllerProvider.notifier);
  }

  late final Directory tempDir;
  late final Project project;
  late final _FakeProjectRepository projectRepository;
  late final _FakeWorkbenchRepository workbenchRepository;
  late final FakeGitBackend gitBackend;
  late final _FakeWorkbenchViewPrefsRepository viewPrefsRepository;
  late final _FakeWorktreeSetupRunner worktreeSetupRunner;
  late final ProviderContainer container;
  late final WorkbenchController _controller;

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

class _FakeWorktreeSetupRunner implements WorktreeSetupRunner {
  WorktreeSetupReport report = WorktreeSetupReport.empty;
  final List<({Project project, Workspace workspace, ProjectConfig config})>
  calls = <({Project project, Workspace workspace, ProjectConfig config})>[];

  @override
  Future<WorktreeSetupReport> run({
    required Project project,
    required Workspace workspace,
    required ProjectConfig config,
  }) async {
    calls.add((project: project, workspace: workspace, config: config));
    return report;
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
