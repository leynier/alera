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
    await closeWorkspaceTabs(workspace: workspace, tabIds: <String>[tabId]);
  }

  @override
  Future<void> closeWorkspaceTabs({
    required Workspace workspace,
    required List<String> tabIds,
  }) async {
    if (closeWorkspaceTabFailure case final Object failure) {
      throw failure;
    }
    final ids = tabIds.toSet();
    if (ids.isEmpty) {
      return;
    }
    final remaining = state
        .tabsFor(workspace.id)
        .where((tab) => !ids.contains(tab.id))
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
        workspace.id: _layoutAfterClosing(
          workspace: workspace,
          remaining: remaining,
          closedTabIds: ids,
        ),
      },
    );
  }

  @override
  Future<WorkspaceTabRecord> createTerminalTab(
    Workspace workspace, {
    String? targetGroupId,
  }) async {
    final tabs = state.tabsFor(workspace.id);
    final tab = _newTerminalTab(workspace.id, tabs.length + 1);
    final nextTabs = <WorkspaceTabRecord>[...tabs, tab];
    _setTabsForWorkspace(workspace.id, nextTabs);
    final layout = _layoutForWorkspace(workspace.id, tabs);
    final groupId = targetGroupId ?? layout.activeGroupId;
    _applyLayout(
      layout.addTabToGroup(groupId: groupId, tabId: tab.id).sanitize(nextTabs),
    );
    return tab;
  }

  @override
  Future<WorkspaceTabRecord> splitWorkbenchGroupWithTerminal({
    required Workspace workspace,
    required String groupId,
    required WorkbenchDropZone zone,
  }) async {
    final tabs = state.tabsFor(workspace.id);
    final tab = _newTerminalTab(workspace.id, tabs.length + 1);
    final nextTabs = <WorkspaceTabRecord>[...tabs, tab];
    _setTabsForWorkspace(workspace.id, nextTabs);
    final layout = _layoutForWorkspace(workspace.id, tabs);
    _applyLayout(
      layout
          .splitWithGroup(
            targetGroupId: groupId,
            zone: zone,
            newGroup: WorkbenchPaneGroup(
              id: _newPaneGroupId(),
              tabIds: <String>[tab.id],
              activeTabId: tab.id,
            ),
          )
          .sanitize(nextTabs),
    );
    return tab;
  }

  @override
  Future<void> moveWorkspaceTab({
    required String workspaceId,
    required String tabId,
    required String targetGroupId,
    required WorkbenchDropZone zone,
    int? index,
  }) async {
    final tabs = state.tabsFor(workspaceId);
    _applyLayout(
      _layoutForWorkspace(workspaceId, tabs)
          .moveTab(
            tabId: tabId,
            targetGroupId: targetGroupId,
            zone: zone,
            newGroupId: _newPaneGroupId(),
            index: index,
          )
          .sanitize(tabs),
    );
  }

  @override
  Future<void> mergeWorkbenchGroupIntoSibling({
    required String workspaceId,
    required String groupId,
  }) async {
    final tabs = state.tabsFor(workspaceId);
    _applyLayout(
      _layoutForWorkspace(
        workspaceId,
        tabs,
      ).mergeGroupIntoSibling(groupId).sanitize(tabs),
    );
  }

  @override
  void updateWorkbenchSplitRatio({
    required String workspaceId,
    required List<int> nodePath,
    required double ratio,
  }) {
    final tabs = state.tabsFor(workspaceId);
    _applyLayout(
      _layoutForWorkspace(
        workspaceId,
        tabs,
      ).updateSplitRatio(nodePath, ratio).sanitize(tabs),
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

  int _nextPaneIndex = 1;

  WorkspaceTabRecord _newTerminalTab(String workspaceId, int ordinal) {
    final now = DateTime.utc(2026, 5, 22);
    final existingIds = state.tabsFor(workspaceId).map((tab) => tab.id).toSet();
    var candidate = ordinal;
    var id = 'tab-$candidate';
    while (existingIds.contains(id)) {
      candidate += 1;
      id = 'tab-$candidate';
    }
    return WorkspaceTabRecord(
      id: id,
      workspaceId: workspaceId,
      title: 'Terminal $candidate',
      createdAt: now,
      updatedAt: now,
    );
  }

  String _newPaneGroupId() => 'pane-${_nextPaneIndex++}';

  WorkbenchLayout _layoutForWorkspace(
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

  WorkbenchLayout _layoutAfterClosing({
    required Workspace workspace,
    required List<WorkspaceTabRecord> remaining,
    required Set<String> closedTabIds,
  }) {
    if (remaining.isEmpty) {
      return WorkbenchLayout.single(
        workspaceId: workspace.id,
        tabIds: const <String>[],
      );
    }
    var layout = _layoutForWorkspace(workspace.id, remaining);
    for (final tabId in closedTabIds) {
      layout = layout.removeTab(tabId);
    }
    return layout.sanitize(remaining);
  }

  void _setTabsForWorkspace(String workspaceId, List<WorkspaceTabRecord> tabs) {
    state = state.copyWith(
      tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
        ...state.tabsByWorkspace,
        workspaceId: tabs,
      },
    );
  }

  void _applyLayout(WorkbenchLayout layout) {
    final activeTabs = <String, String>{...state.activeTabIdByWorkspace};
    final activeTabId = layout.activeTabId;
    if (activeTabId == null) {
      activeTabs.remove(layout.workspaceId);
    } else {
      activeTabs[layout.workspaceId] = activeTabId;
    }
    state = state.copyWith(
      layoutByWorkspace: <String, WorkbenchLayout>{
        ...state.layoutByWorkspace,
        layout.workspaceId: layout,
      },
      activeTabIdByWorkspace: activeTabs,
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
