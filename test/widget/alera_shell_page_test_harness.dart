part of 'alera_shell_page_test.dart';

class _ShellTestAgentStatusController extends AgentStatusController {
  _ShellTestAgentStatusController(this._entries);

  final Map<String, AgentStatusEntry> _entries;

  @override
  Map<String, AgentStatusEntry> build() => _entries;
}

class _ShellTestWorkbenchController extends WorkbenchController {
  _ShellTestWorkbenchController(
    this._bootstrapState, {
    this.renameProjectFailure,
    this.renameWorkspaceFailure,
    this.deleteWorkspaceFailure,
    this.removeProjectFailure,
    this.closeWorkspaceTabFailure,
  });

  final WorkbenchState _bootstrapState;
  final Object? renameProjectFailure;
  final Object? renameWorkspaceFailure;
  final Object? deleteWorkspaceFailure;
  final Object? removeProjectFailure;
  final Object? closeWorkspaceTabFailure;

  @override
  WorkbenchState build() => const WorkbenchState();

  @override
  Future<void> bootstrap() async {
    state = _bootstrapState;
  }

  @override
  Future<void> selectWorkspace({
    required Project project,
    required Workspace workspace,
  }) async {
    state = state.copyWith(
      activeProjectId: project.id,
      activeWorkspaceId: workspace.id,
      viewPrefs: state.viewPrefs.copyWith(
        expandedWorkspaceIds: <String>{
          ...state.viewPrefs.expandedWorkspaceIds,
          workspace.id,
        },
      ),
    );
  }

  @override
  void setActiveTab({required String workspaceId, required String tabId}) {
    final layout = state.layoutFor(workspaceId);
    final groupId = layout?.groupIdForTab(tabId);
    state = state.copyWith(
      activeWorkspaceId: workspaceId,
      activeTabIdByWorkspace: <String, String>{
        ...state.activeTabIdByWorkspace,
        workspaceId: tabId,
      },
      layoutByWorkspace: <String, WorkbenchLayout>{
        ...state.layoutByWorkspace,
        if (layout != null && groupId != null)
          workspaceId: layout.setActiveTab(groupId: groupId, tabId: tabId),
      },
    );
  }

  @override
  Future<void> closeWorkspaceTab({
    required Workspace workspace,
    required String tabId,
  }) async {
    if (closeWorkspaceTabFailure case final Object failure) {
      throw failure;
    }
    final remaining = state
        .tabsFor(workspace.id)
        .where((tab) => tab.id != tabId)
        .toList(growable: false);
    final nextActiveTabIdByWorkspace = <String, String>{
      ...state.activeTabIdByWorkspace,
    };
    if (remaining.isEmpty) {
      nextActiveTabIdByWorkspace.remove(workspace.id);
    } else {
      nextActiveTabIdByWorkspace[workspace.id] = remaining.last.id;
    }
    state = state.copyWith(
      tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
        ...state.tabsByWorkspace,
        workspace.id: remaining,
      },
      activeWorkspaceId:
          remaining.isEmpty && state.activeWorkspaceId == workspace.id
          ? null
          : state.activeWorkspaceId,
      activeTabIdByWorkspace: nextActiveTabIdByWorkspace,
      layoutByWorkspace: <String, WorkbenchLayout>{
        ...state.layoutByWorkspace,
        workspace.id: WorkbenchLayout.single(
          workspaceId: workspace.id,
          tabIds: <String>[for (final tab in remaining) tab.id],
        ),
      },
    );
  }

  @override
  Future<void> deleteWorkspace({
    required Project project,
    required Workspace workspace,
    bool deleteBranch = true,
  }) async {
    if (deleteWorkspaceFailure case final Object failure) {
      throw failure;
    }
    final nextWorkspaces = <Workspace>[
      for (final candidate in state.workspacesFor(project.id))
        if (candidate.id != workspace.id) candidate,
    ];
    final nextTabs = <String, List<WorkspaceTabRecord>>{
      for (final entry in state.tabsByWorkspace.entries)
        if (entry.key != workspace.id) entry.key: entry.value,
    };
    final nextLayouts = <String, WorkbenchLayout>{
      for (final entry in state.layoutByWorkspace.entries)
        if (entry.key != workspace.id) entry.key: entry.value,
    };
    final nextActiveTabs = <String, String>{
      for (final entry in state.activeTabIdByWorkspace.entries)
        if (entry.key != workspace.id) entry.key: entry.value,
    };
    final nextExpanded = Set<String>.from(state.viewPrefs.expandedWorkspaceIds)
      ..remove(workspace.id);
    state = state.copyWith(
      workspacesByProject: <String, List<Workspace>>{
        ...state.workspacesByProject,
        project.id: nextWorkspaces,
      },
      tabsByWorkspace: nextTabs,
      layoutByWorkspace: nextLayouts,
      activeTabIdByWorkspace: nextActiveTabs,
      activeWorkspaceId: state.activeWorkspaceId == workspace.id
          ? null
          : state.activeWorkspaceId,
      viewPrefs: state.viewPrefs.copyWith(expandedWorkspaceIds: nextExpanded),
    );
  }

  @override
  Future<void> removeProject(String projectId) async {
    if (removeProjectFailure case final Object failure) {
      throw failure;
    }
    final removedWorkspaceIds = state
        .workspacesFor(projectId)
        .map((workspace) => workspace.id)
        .toSet();
    final nextProjects = <Project>[
      for (final project in state.projects)
        if (project.id != projectId) project,
    ];
    final nextWorkspacesByProject = <String, List<Workspace>>{
      for (final entry in state.workspacesByProject.entries)
        if (entry.key != projectId) entry.key: entry.value,
    };
    final nextTabs = <String, List<WorkspaceTabRecord>>{
      for (final entry in state.tabsByWorkspace.entries)
        if (!removedWorkspaceIds.contains(entry.key)) entry.key: entry.value,
    };
    final nextLayouts = <String, WorkbenchLayout>{
      for (final entry in state.layoutByWorkspace.entries)
        if (!removedWorkspaceIds.contains(entry.key)) entry.key: entry.value,
    };
    final nextActiveTabs = <String, String>{
      for (final entry in state.activeTabIdByWorkspace.entries)
        if (!removedWorkspaceIds.contains(entry.key)) entry.key: entry.value,
    };
    final nextCollapsedProjects = Set<String>.from(
      state.viewPrefs.collapsedProjectIds,
    )..remove(projectId);
    final nextSelectedProjects = Set<String>.from(
      state.viewPrefs.selectedProjectIds,
    )..remove(projectId);
    final nextExpanded = Set<String>.from(state.viewPrefs.expandedWorkspaceIds)
      ..removeAll(removedWorkspaceIds);
    state = state.copyWith(
      projects: nextProjects,
      workspacesByProject: nextWorkspacesByProject,
      tabsByWorkspace: nextTabs,
      layoutByWorkspace: nextLayouts,
      activeTabIdByWorkspace: nextActiveTabs,
      activeProjectId: nextProjects.isEmpty ? null : nextProjects.first.id,
      activeWorkspaceId: null,
      viewPrefs: state.viewPrefs.copyWith(
        collapsedProjectIds: nextCollapsedProjects,
        selectedProjectIds: nextSelectedProjects,
        expandedWorkspaceIds: nextExpanded,
      ),
    );
  }

  @override
  Future<void> renameProject({
    required String projectId,
    required String name,
  }) async {
    if (renameProjectFailure case final Object failure) {
      throw failure;
    }
    final trimmed = name.trim();
    state = state.copyWith(
      projects: <Project>[
        for (final project in state.projects)
          if (project.id == projectId)
            project.copyWith(name: trimmed)
          else
            project,
      ],
    );
  }

  @override
  Future<void> renameWorkspace({
    required String workspaceId,
    required String name,
  }) async {
    if (renameWorkspaceFailure case final Object failure) {
      throw failure;
    }
    final trimmed = name.trim();
    final nextByProject = <String, List<Workspace>>{
      for (final entry in state.workspacesByProject.entries)
        entry.key: <Workspace>[
          for (final workspace in entry.value)
            if (workspace.id == workspaceId)
              workspace.copyWith(name: trimmed)
            else
              workspace,
        ],
    };
    state = state.copyWith(workspacesByProject: nextByProject);
  }

  @override
  Future<void> renameWorkspaceTab({
    required String tabId,
    required String title,
  }) async {
    final trimmed = title.trim();
    state = state.copyWith(
      tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
        for (final entry in state.tabsByWorkspace.entries)
          entry.key: <WorkspaceTabRecord>[
            for (final tab in entry.value)
              if (tab.id == tabId) tab.copyWith(title: trimmed) else tab,
          ],
      },
    );
  }

  @override
  void setActiveWorkspaceTab({
    required String workspaceId,
    required String groupId,
    required String tabId,
  }) {
    final layout = state.layoutFor(workspaceId);
    state = state.copyWith(
      activeWorkspaceId: workspaceId,
      activeTabIdByWorkspace: <String, String>{
        ...state.activeTabIdByWorkspace,
        workspaceId: tabId,
      },
      layoutByWorkspace: <String, WorkbenchLayout>{
        ...state.layoutByWorkspace,
        if (layout != null)
          workspaceId: layout.setActiveTab(groupId: groupId, tabId: tabId),
      },
    );
  }
}

class _ShellSettingsController extends SettingsController {
  _ShellSettingsController(this._seed);

  final AleraSettings _seed;

  @override
  AleraSettings build() => _seed;
}

class _ShellPumpHarness {
  const _ShellPumpHarness({required this.controller, required this.runtime});

  final _ShellTestWorkbenchController controller;
  final _FakeTerminalRuntime runtime;
}

class _FakeTerminalRuntime implements TerminalRuntime {
  final Map<String, _FakeTerminalSessionHandle> _sessions =
      <String, _FakeTerminalSessionHandle>{};
  final StreamController<TerminalRuntimeExitEvent> _exitController =
      StreamController<TerminalRuntimeExitEvent>.broadcast();
  final List<String> closedWorkspaceIds = <String>[];
  final List<String> closedTabIds = <String>[];

  @override
  Stream<TerminalRuntimeExitEvent> get exits => _exitController.stream;

  @override
  TerminalSessionHandle sessionFor({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    return _sessions.putIfAbsent(
      tab.id,
      () => _FakeTerminalSessionHandle(workspace: workspace, tab: tab),
    );
  }

  @override
  void closeTab(String tabId) {
    closedTabIds.add(tabId);
    _sessions.remove(tabId)?.dispose();
  }

  /// Total `requestFocus()` calls across every session this runtime created.
  int get totalFocusRequests => _sessions.values.fold<int>(
    0,
    (sum, session) => sum + session.requestFocusCalls,
  );

  /// Tab ids that received at least one `requestFocus()` call.
  Iterable<String> get focusedTabIds => _sessions.entries
      .where((entry) => entry.value.requestFocusCalls > 0)
      .map((entry) => entry.key);

  void emitExit({
    required String workspaceId,
    required String tabId,
    int exitCode = 0,
  }) {
    _exitController.add(
      TerminalRuntimeExitEvent(
        workspaceId: workspaceId,
        tabId: tabId,
        exitCode: exitCode,
      ),
    );
  }

  @override
  void closeWorkspace(String workspaceId) {
    closedWorkspaceIds.add(workspaceId);
    final removed = _sessions.entries
        .where((entry) => entry.value.workspaceId == workspaceId)
        .map((entry) => entry.key)
        .toList(growable: false);
    for (final tabId in removed) {
      _sessions.remove(tabId)?.dispose();
    }
  }

  @override
  void dispose() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
    unawaited(_exitController.close());
  }
}

class _FakeTerminalSessionHandle extends TerminalSessionHandle {
  _FakeTerminalSessionHandle({required this.workspace, required this.tab});

  final Workspace workspace;
  final WorkspaceTabRecord tab;
  bool _started = false;

  @override
  String get tabId => tab.id;

  @override
  String get workspaceId => workspace.id;

  @override
  String get displayTitle => tab.title;

  @override
  bool get isRunning => _started;

  @override
  bool get isStarting => false;

  @override
  String? get errorMessage => null;

  @override
  Future<void> ensureStarted() async {
    _started = true;
  }

  @override
  Future<void> restart() => ensureStarted();

  @override
  TerminalVisibilityLease acquireVisibility() =>
      const NoopTerminalVisibilityLease();

  @override
  Widget buildView({
    Key? key,
    bool autofocus = false,
    FocusOnKeyEventCallback? onKeyEvent,
  }) {
    return Center(
      key: ValueKey<String>('fake-terminal-${tab.id}'),
      child: Text('Terminal ${tab.title}'),
    );
  }

  int requestFocusCalls = 0;

  @override
  void requestFocus() {
    requestFocusCalls += 1;
  }
}

class _NoopProcessRunner implements ProcessRunner {
  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
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
