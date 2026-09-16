part of 'workbench_controller.dart';

mixin _WorkbenchControllerInternals on _$WorkbenchController {
  final Uuid _uuid = const Uuid();
  bool _disposed = false;
  bool _transferringWorkspace = false;
  int _workspaceSelectionRevision = 0;
  bool _refreshAfterTransfer = false;
  Future<void> _workspaceSyncQueue = Future<void>.value();
  final Map<String, String> _transferredTabOwners = {};
  Future<void> _refreshProjectAfterTransfer(Project project);

  ProjectsService get _projectsService => ref.read(projectsServiceProvider);

  WorkbenchRepository get _repository => ref.read(workbenchRepositoryProvider);

  WorkspaceGraphRepository get _workspaceGraphRepository =>
      ref.read(workspaceGraphRepositoryProvider);

  WorkspaceService get _workspaceService => ref.read(workspaceServiceProvider);

  WorkspaceTabService get _workspaceTabService =>
      ref.read(workspaceTabServiceProvider);

  PromptWorkspaceRuntimeClient get _promptWorkspaceRuntimeClient {
    return PromptWorkspaceRuntimeClient(
      ref.read(runtimeHostClientProvider),
      beforeAccess: ref.read(runtimeStateMigrationProvider).ensureMigrated,
    );
  }

  WorkbenchViewPrefsRepository? get _viewPrefsRepository =>
      ref.read(workbenchViewPrefsRepositoryProvider);

  StreamSubscription<WorkspaceSectionSnapshot>? _sectionsSub;
  StreamSubscription<List<Project>>? _projectsSub;
  StreamSubscription<WorkbenchViewPrefs>? _viewPrefsSub;
  final Map<String, StreamSubscription<List<Workspace>>> _workspaceSubs =
      <String, StreamSubscription<List<Workspace>>>{};
  final Map<String, StreamSubscription<List<WorkspaceTabRecord>>> _tabSubs =
      <String, StreamSubscription<List<WorkspaceTabRecord>>>{};
  // Tracks which project each workspace-tab subscription belongs to, so subs
  // can be pruned by project without relying on the (already-mutated) state.
  final Map<String, String> _tabSubProjectIds = <String, String>{};
  final Set<String> _reconcilingProjectIds = <String>{};
  final Set<String> _loadingLayoutWorkspaceIds = <String>{};
  final Set<String> _closingTabWorkspaceIds = <String>{};
  final Set<String> _closedTabIds = <String>{};
  final Set<String> _workspaceIdsWithClearedLayout = <String>{};
  final Map<String, int> _workspaceSleepGeneration = <String, int>{};
  final Map<String, int> _panelSelectionRevisionByWorkspace = <String, int>{};
  Future<void>? _fileOpenQueue;

  final WorkspaceTabFocusHistory _tabFocusHistory = WorkspaceTabFocusHistory();
  final WorktreeNavigationHistory _worktreeNavigationHistory =
      WorktreeNavigationHistory();

  bool _bootstrapStarted = false;

  bool get canGoBack {
    _pruneWorktreeNavigationHistory();
    return _worktreeNavigationHistory.canGoBack;
  }

  bool get canGoForward {
    _pruneWorktreeNavigationHistory();
    return _worktreeNavigationHistory.canGoForward;
  }

  bool _isLiveWorktreeNavigationTarget(WorktreeNavigationTarget target) {
    final project = _projectById(state.projects, target.projectId);
    if (project == null) {
      return false;
    }
    return state
        .workspacesFor(project.id)
        .any((workspace) => workspace.id == target.workspaceId);
  }

  void _pruneWorktreeNavigationHistory() {
    _worktreeNavigationHistory.prune(_isLiveWorktreeNavigationTarget);
  }

  void _notifyNavigationHistoryChanged() {
    if (!_disposed) {
      state = state.copyWith();
    }
  }

  Future<void> _persistViewPrefs() async {
    final repo = _viewPrefsRepository;
    if (repo == null) {
      return;
    }
    try {
      await repo.save(state.viewPrefs);
    } catch (error) {
      _recordLayoutError(error);
    }
  }

  Project? _projectById(Iterable<Project> projects, String? projectId) {
    if (projectId == null) {
      return null;
    }
    for (final project in projects) {
      if (project.id == projectId) {
        return project;
      }
    }
    return null;
  }

  Workspace? _workspaceById(String workspaceId) {
    return state.workspacesByProject.values
        .expand((workspaces) => workspaces)
        .where((workspace) => workspace.id == workspaceId)
        .firstOrNull;
  }

  Future<void> _releaseHostedReviewTab(
    Workspace workspace,
    WorkspaceTabRecord tab, {
    String? fallbackWorkspacePath,
  }) async {
    final retentionId = tab.gitDiffHostedReviewRetentionId;
    if (tab.gitDiffSource != WorkspaceGitDiffSource.pullRequest ||
        retentionId == null) {
      return;
    }
    await _releaseHostedReviewRetention(
      workspace: workspace,
      relativeRoot: tab.gitDiffRoot,
      retentionId: retentionId,
      fallbackWorkspacePath: fallbackWorkspacePath,
    );
  }

  Future<void> _releaseHostedReviewRetention({
    required Workspace workspace,
    required String? relativeRoot,
    required String retentionId,
    String? fallbackWorkspacePath,
  }) async {
    final path = relativeRoot == null
        ? workspace.path
        : sourceControlRootAbsolutePath(
            workspacePath: workspace.path,
            relativeRoot: relativeRoot,
          );
    try {
      await ref
          .read(gitBackendProvider)
          .releaseHostedReviewRange(path: path, retentionId: retentionId);
    } catch (_) {
      if (fallbackWorkspacePath == null ||
          fallbackWorkspacePath == workspace.path) {
        return;
      }
      final fallbackPath = relativeRoot == null
          ? fallbackWorkspacePath
          : sourceControlRootAbsolutePath(
              workspacePath: fallbackWorkspacePath,
              relativeRoot: relativeRoot,
            );
      try {
        await ref
            .read(gitBackendProvider)
            .releaseHostedReviewRange(
              path: fallbackPath,
              retentionId: retentionId,
            );
      } catch (_) {
        // A stale retention ref must never make a persisted tab impossible to close.
      }
    }
  }

  Future<void> _persistHostedReviewRetention({
    required Workspace workspace,
    required String? relativeRoot,
    required String retentionId,
  }) {
    final path = relativeRoot == null
        ? workspace.path
        : sourceControlRootAbsolutePath(
            workspacePath: workspace.path,
            relativeRoot: relativeRoot,
          );
    return ref
        .read(gitBackendProvider)
        .persistHostedReviewRange(path: path, retentionId: retentionId);
  }

  void _releaseHostedReviewTabsInBackground(
    Workspace workspace,
    Iterable<WorkspaceTabRecord> tabs,
  ) {
    for (final tab in tabs) {
      unawaited(_releaseHostedReviewTab(workspace, tab));
    }
  }

  Future<void> _activateAddedProject(Project project) async {
    await _reconcileProjectWorkspaces(project);
    // Expand the project (remove from collapsed set if a stale id lingered).
    // Selection set is a positive filter - leave it untouched so we don't
    // accidentally start showing this brand-new project alone.
    final prefs = state.viewPrefs;
    final nextCollapsed = Set<String>.from(prefs.collapsedProjectIds)
      ..remove(project.id);
    final changedPrefs =
        nextCollapsed.length != prefs.collapsedProjectIds.length;
    final expandedPrefs = changedPrefs
        ? prefs.copyWith(collapsedProjectIds: nextCollapsed)
        : prefs;
    final nextViewPrefs = expandedPrefs;
    final prefsChanged = !identical(nextViewPrefs, prefs);
    state = state.copyWith(
      viewPrefs: nextViewPrefs,
      activeProjectId: project.id,
      activeWorkspaceId: null,
      error: null,
    );
    if (prefsChanged) {
      unawaited(_persistViewPrefs());
    }
  }

  String? _resolveActiveWorkspaceId({
    required String? activeProjectId,
    required Map<String, List<Workspace>> workspacesByProject,
    required String? preferredWorkspaceId,
  }) {
    if (activeProjectId != null) {
      final workspaces =
          workspacesByProject[activeProjectId] ?? const <Workspace>[];
      // Keep an explicit selection only while it still belongs to the active
      // project. Missing or stale selections intentionally stay empty.
      if (preferredWorkspaceId != null &&
          workspaces.any((workspace) => workspace.id == preferredWorkspaceId)) {
        return preferredWorkspaceId;
      }
      return null;
    }
    return null;
  }

  void _ensureSelectionHasTab() {
    final workspace = state.activeWorkspace;
    if (workspace == null) {
      return;
    }
    if (_closingTabWorkspaceIds.contains(workspace.id)) {
      return;
    }
    if (state.tabsFor(workspace.id).isNotEmpty &&
        state.layoutFor(workspace.id) == null &&
        !_workspaceIdsWithClearedLayout.contains(workspace.id)) {
      unawaited(_loadLayoutForWorkspace(workspace.id));
    }
  }

  void _maybeEnsurePrimaryTerminal(Workspace workspace) {}

  Future<void> _loadLayoutForWorkspace(String workspaceId) async {
    if (!_loadingLayoutWorkspaceIds.add(workspaceId)) {
      return;
    }
    final sleepGeneration = _workspaceSleepGeneration[workspaceId] ?? 0;
    try {
      final tabs = await _workspaceTabService.listTabs(workspaceId);
      if (_isStaleWorkspaceOpen(workspaceId, sleepGeneration)) {
        return;
      }
      final layout = await _ensureWorkbenchLayout(
        workspaceId,
        tabs,
        sleepGeneration: sleepGeneration,
      );
      if (_isStaleWorkspaceOpen(workspaceId, sleepGeneration)) {
        return;
      }
      await _applyLayout(layout, persist: false);
    } catch (error) {
      if (!_disposed) {
        state = state.copyWith(error: error.toString());
      }
    } finally {
      _loadingLayoutWorkspaceIds.remove(workspaceId);
    }
  }

  Future<WorkbenchLayout> _ensureWorkbenchLayout(
    String workspaceId,
    List<WorkspaceTabRecord> tabs, {
    int? sleepGeneration,
  }) async {
    final generation =
        sleepGeneration ?? (_workspaceSleepGeneration[workspaceId] ?? 0);
    final stored = await _repository.findWorkbenchLayout(workspaceId);
    if (_isStaleWorkspaceOpen(workspaceId, generation)) {
      return stored ??
          WorkbenchLayout.single(
            workspaceId: workspaceId,
            tabIds: const <String>[],
          );
    }
    final layout =
        stored ??
        WorkbenchLayout.single(
          workspaceId: workspaceId,
          tabIds: <String>[for (final tab in tabs) tab.id],
        );
    final sanitized = layout.sanitize(tabs);
    if (stored == null || sanitized != stored) {
      if (_isStaleWorkspaceOpen(workspaceId, generation)) {
        return stored ??
            WorkbenchLayout.single(
              workspaceId: workspaceId,
              tabIds: const <String>[],
            );
      }
      await _repository.upsertWorkbenchLayout(sanitized);
    }
    return sanitized;
  }

  WorkbenchLayout _layoutForMutation(
    String workspaceId,
    List<WorkspaceTabRecord> tabs,
  ) {
    return (state.layoutFor(workspaceId) ??
            WorkbenchLayout.single(
              workspaceId: workspaceId,
              tabIds: <String>[for (final tab in tabs) tab.id],
            ))
        .sanitize(tabs);
  }

  Future<void> _applyLayout(
    WorkbenchLayout layout, {
    required bool persist,
  }) async {
    // Keep the persisted tab tree in sync with records. Panel focus and
    // splits live in view prefs; this must not rewrite them.
    layout = (state.layoutFor(layout.workspaceId) ?? layout).sanitize(
      state.tabsFor(layout.workspaceId),
    );
    final nextLayouts = Map<String, WorkbenchLayout>.from(
      state.layoutByWorkspace,
    )..[layout.workspaceId] = layout;
    state = state.copyWith(layoutByWorkspace: nextLayouts);
    if (persist) {
      _persistLayoutInBackground(layout);
    }
  }

  void _persistLayoutInBackground(WorkbenchLayout layout) {
    unawaited(
      _repository
          .upsertWorkbenchLayout(layout)
          .then<void>((_) {})
          .catchError(_recordLayoutError),
    );
  }

  void _recordLayoutError(Object error) {
    if (!_disposed) {
      state = state.copyWith(error: error.toString());
    }
  }

  bool _isStaleWorkspaceOpen(String workspaceId, int sleepGeneration) {
    return _disposed ||
        (_workspaceSleepGeneration[workspaceId] ?? 0) != sleepGeneration ||
        _workspaceIdsWithClearedLayout.contains(workspaceId);
  }

  void _selectOpenedWorkspaceTab({
    required String workspaceId,
    required WorkspaceTabRecord tab,
    required bool existedBeforeRequest,
    String? targetGroupId,
  }) {
    final key = WorkspacePanel.tabKey(tab.id);
    var panel = state.workspacePanelFor(workspaceId);
    final currentGroupId = targetGroupId == null
        ? null
        : (panel
                  .ensuredMainLayout(workspaceId)
                  .groups
                  .containsKey(targetGroupId)
              ? panel.ensuredMainLayout(workspaceId).groupIdForTab(key)
              : panel.ensuredLayout(workspaceId).groupIdForTab(key));
    if (!existedBeforeRequest &&
        targetGroupId != null &&
        panel.treeForKey(key) != null &&
        currentGroupId != targetGroupId) {
      panel = panel.closeKey(key);
    }
    _panelSelectionRevisionByWorkspace[workspaceId] =
        (_panelSelectionRevisionByWorkspace[workspaceId] ?? 0) + 1;
    final next = panel.select(key, groupId: targetGroupId);
    _saveWorkspacePanel(
      workspaceId,
      next,
      reveal: next.treeForKey(key) == WorkspacePanelTree.right,
    );
  }

  Future<void> _discardStaleOpenedTab(
    WorkspaceTabRecord tab, {
    bool existedBeforeRequest = false,
  }) async {
    if (existedBeforeRequest &&
        (_workspaceSleepGeneration[tab.workspaceId] ?? 0) == 0 &&
        !_workspaceIdsWithClearedLayout.contains(tab.workspaceId)) {
      return;
    }
    try {
      await _workspaceTabService.closeTab(tab.id);
    } catch (_) {
      // A late open must not outlive sleep even if persist fails.
    }
    ref.read(terminalRuntimeProvider).closeTab(tab.id);
    ref.read(editorSessionRegistryProvider).forget(tab.id);
  }

  List<WorkspaceTabRecord> _tabsWithoutClosedIds(
    List<WorkspaceTabRecord> tabs,
  ) {
    if (_closedTabIds.isEmpty) {
      return tabs;
    }
    return <WorkspaceTabRecord>[
      for (final tab in tabs)
        if (!_closedTabIds.contains(tab.id)) tab,
    ];
  }

  bool _isClosedTabId(String tabId) => _closedTabIds.contains(tabId);

  void _setTabsForWorkspace(String workspaceId, List<WorkspaceTabRecord> tabs) {
    final nextTabs = Map<String, List<WorkspaceTabRecord>>.from(
      state.tabsByWorkspace,
    )..[workspaceId] = _tabsWithoutClosedIds(tabs);
    state = state.copyWith(tabsByWorkspace: nextTabs);
    _pruneExplorerSessions();
  }

  void _pruneExplorerSessions() {
    final store = ref.read(workspaceExplorerSessionStoreProvider);
    store.retain(<String>{
      if (state.activeWorkspaceId case final String id) id,
      for (final entry in state.tabsByWorkspace.entries)
        if (entry.value.isNotEmpty) entry.key,
    });
  }

  String _newPaneGroupId() => 'pane-${_uuid.v4()}';

  void _setActiveTabInternal({
    required String workspaceId,
    required String tabId,
    String? groupId,
  }) {
    final panel = state.workspacePanelFor(workspaceId);
    final key = WorkspacePanel.tabKey(tabId);
    _panelSelectionRevisionByWorkspace[workspaceId] =
        (_panelSelectionRevisionByWorkspace[workspaceId] ?? 0) + 1;
    final next = panel.select(key, groupId: groupId);
    _saveWorkspacePanel(
      workspaceId,
      next,
      reveal: next.treeForKey(key) == WorkspacePanelTree.right,
    );
  }

  Future<void> _reconcileProjectWorkspaces(Project project) async {
    if (!_reconcilingProjectIds.add(project.id)) {
      return;
    }
    try {
      await _workspaceService.reconcile(project);
    } catch (error) {
      if (!_disposed) {
        state = state.copyWith(
          error: 'Failed to prepare workspace for "${project.name}": $error',
        );
      }
    } finally {
      _reconcilingProjectIds.remove(project.id);
    }
  }

  void _focusPanelTerminal(String workspaceId, String? key);

  void _seedNewWorkspacePanel(String workspaceId);

  void _saveWorkspacePanel(
    String workspaceId,
    WorkspacePanel panel, {
    bool reveal = false,
    bool recordFocus = true,
    bool requestTerminalFocus = true,
  }) {
    final previousFocus =
        state.viewPrefs.workspacePanels[workspaceId]?.focusedKey;
    final focusedTabId = WorkspacePanel.tabId(panel.focusedKey);
    final alreadyStored = state.viewPrefs.workspacePanels[workspaceId] == panel;
    final alreadyRevealed = !reveal || state.viewPrefs.rightSidebarVisible;
    final alreadyActive =
        focusedTabId == null ||
        state.activeTabIdByWorkspace[workspaceId] == focusedTabId;
    if (alreadyStored && alreadyRevealed && alreadyActive) {
      if (recordFocus && focusedTabId != null) {
        _tabFocusHistory.record(workspaceId, focusedTabId);
      }
      return;
    }
    state = state.copyWith(
      viewPrefs: state.viewPrefs.copyWith(
        workspacePanels: <String, WorkspacePanel>{
          ...state.viewPrefs.workspacePanels,
          workspaceId: panel,
        },
        rightSidebarVisible: reveal
            ? true
            : state.viewPrefs.rightSidebarVisible,
      ),
      activeTabIdByWorkspace: focusedTabId == null
          ? state.activeTabIdByWorkspace
          : <String, String>{
              ...state.activeTabIdByWorkspace,
              workspaceId: focusedTabId,
            },
    );
    if (!alreadyStored || !alreadyRevealed) {
      unawaited(_persistViewPrefs());
    }
    if (recordFocus && focusedTabId != null) {
      _tabFocusHistory.record(workspaceId, focusedTabId);
    }
    if (requestTerminalFocus && previousFocus != panel.focusedKey) {
      _focusPanelTerminal(workspaceId, panel.focusedKey);
    }
  }
}
