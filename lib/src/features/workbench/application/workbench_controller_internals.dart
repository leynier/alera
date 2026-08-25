part of 'workbench_controller.dart';

mixin _WorkbenchControllerInternals on _$WorkbenchController {
  final Uuid _uuid = const Uuid();
  bool _disposed = false;

  ProjectsService get _projectsService => ref.read(projectsServiceProvider);

  WorkbenchRepository get _repository => ref.read(workbenchRepositoryProvider);

  WorkspaceGraphRepository get _workspaceGraphRepository =>
      ref.read(workspaceGraphRepositoryProvider);

  WorkspaceService get _workspaceService => ref.read(workspaceServiceProvider);

  WorkspaceTabService get _workspaceTabService =>
      ref.read(workspaceTabServiceProvider);

  WorkspaceBrowserTabService get _workspaceBrowserTabService =>
      ref.read(workspaceBrowserTabServiceProvider);

  MobileEmulatorService get _mobileEmulatorService =>
      ref.read(mobileEmulatorServiceProvider);

  WorkbenchViewPrefsRepository? get _viewPrefsRepository =>
      ref.read(workbenchViewPrefsRepositoryProvider);

  StreamSubscription<List<Project>>? _projectsSub;
  StreamSubscription<WorkbenchViewPrefs>? _viewPrefsSub;
  final Map<String, StreamSubscription<List<Workspace>>> _workspaceSubs =
      <String, StreamSubscription<List<Workspace>>>{};
  final Map<String, StreamSubscription<List<WorkspaceTabRecord>>> _tabSubs =
      <String, StreamSubscription<List<WorkspaceTabRecord>>>{};
  // Tracks which project each workspace-tab subscription belongs to, so subs
  // can be pruned by project without relying on the (already-mutated) state.
  final Map<String, String> _tabSubProjectIds = <String, String>{};
  final Set<String> _ensuringMainWorkspaceProjectIds = <String>{};
  final Set<String> _loadingLayoutWorkspaceIds = <String>{};
  final Set<String> _closingTabWorkspaceIds = <String>{};
  final Set<String> _workspaceIdsWithClearedLayout = <String>{};
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
    } catch (_) {
      // Persistence is best-effort; never surface an error from the UI path.
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
    await _ensureMainWorkspaceForProject(project);
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
        state.layoutFor(workspace.id) == null) {
      unawaited(_loadLayoutForWorkspace(workspace.id));
    }
  }

  Future<void> _loadLayoutForWorkspace(String workspaceId) async {
    if (!_loadingLayoutWorkspaceIds.add(workspaceId)) {
      return;
    }
    try {
      final tabs = await _workspaceTabService.listTabs(workspaceId);
      final layout = await _ensureWorkbenchLayout(workspaceId, tabs);
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
    List<WorkspaceTabRecord> tabs,
  ) async {
    final stored = await _repository.findWorkbenchLayout(workspaceId);
    final layout =
        stored ??
        WorkbenchLayout.single(
          workspaceId: workspaceId,
          tabIds: <String>[for (final tab in tabs) tab.id],
        );
    final sanitized = layout.sanitize(tabs);
    if (stored == null || sanitized != stored) {
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
    final nextLayouts = Map<String, WorkbenchLayout>.from(
      state.layoutByWorkspace,
    )..[layout.workspaceId] = layout;
    state = state.copyWith(
      layoutByWorkspace: nextLayouts,
      activeTabIdByWorkspace: _activeTabsWithLayout(layout),
    );
    final activeTabId = layout.activeTabId;
    if (activeTabId != null) {
      _tabFocusHistory.record(layout.workspaceId, activeTabId);
    }
    if (persist) {
      await _repository.upsertWorkbenchLayout(layout);
    }
  }

  void _applyLayoutInBackground(
    WorkbenchLayout layout, {
    required bool persist,
  }) {
    unawaited(
      _applyLayout(layout, persist: persist).catchError(_recordLayoutError),
    );
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

  Map<String, String> _activeTabsWithLayout(WorkbenchLayout layout) {
    final activeTabs = Map<String, String>.from(state.activeTabIdByWorkspace);
    final activeTabId = layout.activeTabId;
    if (activeTabId == null) {
      activeTabs.remove(layout.workspaceId);
    } else {
      activeTabs[layout.workspaceId] = activeTabId;
    }
    return activeTabs;
  }

  void _setTabsForWorkspace(String workspaceId, List<WorkspaceTabRecord> tabs) {
    _removeMissingCodexDrafts(workspaceId, tabs);
    final nextTabs = Map<String, List<WorkspaceTabRecord>>.from(
      state.tabsByWorkspace,
    )..[workspaceId] = tabs;
    state = state.copyWith(tabsByWorkspace: nextTabs);
  }

  void _removeMissingCodexDrafts(
    String workspaceId,
    List<WorkspaceTabRecord> tabs,
  ) {
    final retainedIds = <String>{for (final tab in tabs) tab.id};
    _removeCodexDrafts(
      state.tabsFor(workspaceId).where((tab) => !retainedIds.contains(tab.id)),
    );
  }

  void _removeCodexDrafts(Iterable<WorkspaceTabRecord> tabs) {
    final draftStore = ref.read(codexComposerDraftStoreProvider);
    for (final tab in tabs) {
      if (tab.kind == WorkspaceTabKind.codex) draftStore.remove(tab.id);
    }
  }

  String _newPaneGroupId() => 'pane-${_uuid.v4()}';

  void _setActiveTabInternal({
    required String workspaceId,
    required String tabId,
    String? groupId,
  }) {
    final layout = state.layoutFor(workspaceId);
    final resolvedGroupId = groupId ?? layout?.groupIdForTab(tabId);
    if (layout != null && resolvedGroupId != null) {
      final nextLayout = layout.setActiveTab(
        groupId: resolvedGroupId,
        tabId: tabId,
      );
      _applyLayoutInBackground(nextLayout, persist: true);
      return;
    }
    final next = Map<String, String>.from(state.activeTabIdByWorkspace)
      ..[workspaceId] = tabId;
    state = state.copyWith(activeTabIdByWorkspace: next);
    _tabFocusHistory.record(workspaceId, tabId);
  }

  Future<void> _ensureMainWorkspaceForProject(Project project) async {
    if (!_ensuringMainWorkspaceProjectIds.add(project.id)) {
      return;
    }
    try {
      await _workspaceService.ensureMainWorkspace(project);
      await _workspaceService.reconcile(project);
    } catch (error) {
      if (!_disposed) {
        state = state.copyWith(
          error: 'Failed to prepare workspace for "${project.name}": $error',
        );
      }
    } finally {
      _ensuringMainWorkspaceProjectIds.remove(project.id);
    }
  }
}
