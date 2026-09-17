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
  void _onWorkspacesChanged(Project project, List<Workspace> workspaces);
  void _applyWorkspacesChanged(Project project, List<Workspace> workspaces);
  void _applyTabsChanged(String workspaceId, List<WorkspaceTabRecord> tabs);
  void _recordLayoutError(Object error);
  void _maybeEnsurePrimaryTerminal(Workspace workspace);

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

  void _focusPanelTerminal(String workspaceId, String? key);

  void _seedNewWorkspacePanel(String workspaceId);
}
