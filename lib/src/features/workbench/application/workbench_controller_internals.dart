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

  final WorkspaceTabFocusHistory _tabFocusHistory = WorkspaceTabFocusHistory();

  bool _bootstrapStarted = false;

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

  WorkbenchContextPanelTab _supportedContextPanelTabForProjectWorkspace({
    required Project? project,
    required Workspace? workspace,
    required WorkbenchViewPrefs prefs,
    required WorkbenchContextPanelTab tab,
  }) {
    if (workspace == null) {
      return tab;
    }
    final sourceControlScope = WorkspaceSourceControlScope.resolve(
      project: project,
      workspace: workspace,
      prefs: prefs,
    );
    if (sourceControlScope == null && tab == WorkbenchContextPanelTab.gitDiff) {
      return WorkbenchContextPanelTab.explorer;
    }
    return tab;
  }

  WorkbenchViewPrefs _viewPrefsForProjectContext({
    required Project? project,
    required Workspace? workspace,
    required WorkbenchViewPrefs prefs,
  }) {
    final activeContextPanelTab = _supportedContextPanelTabForProjectWorkspace(
      project: project,
      workspace: workspace,
      prefs: prefs,
      tab: prefs.activeContextPanelTab,
    );
    if (activeContextPanelTab == prefs.activeContextPanelTab) {
      return prefs;
    }
    return prefs.copyWith(activeContextPanelTab: activeContextPanelTab);
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

  Workspace? _workspaceById(
    Map<String, List<Workspace>> workspacesByProject,
    String? workspaceId,
  ) {
    if (workspaceId == null) {
      return null;
    }
    for (final workspaces in workspacesByProject.values) {
      for (final workspace in workspaces) {
        if (workspace.id == workspaceId) {
          return workspace;
        }
      }
    }
    return null;
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
    final nextViewPrefs = _viewPrefsForProjectContext(
      project: project,
      workspace: null,
      prefs: expandedPrefs,
    );
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
    final nextTabs = Map<String, List<WorkspaceTabRecord>>.from(
      state.tabsByWorkspace,
    )..[workspaceId] = tabs;
    state = state.copyWith(tabsByWorkspace: nextTabs);
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
