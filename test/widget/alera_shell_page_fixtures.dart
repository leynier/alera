part of 'alera_shell_page_test.dart';

WorkbenchLayout _panelKeyedLayout(WorkbenchLayout layout) {
  String keyFor(String id) => id.startsWith('tab:') || id.startsWith('tool:')
      ? id
      : WorkspacePanel.tabKey(id);
  return WorkbenchLayout(
    workspaceId: layout.workspaceId,
    root: layout.root,
    groups: <String, WorkbenchPaneGroup>{
      for (final entry in layout.groups.entries)
        entry.key: WorkbenchPaneGroup(
          id: entry.value.id,
          tabIds: <String>[for (final id in entry.value.tabIds) keyFor(id)],
          activeTabId: entry.value.activeTabId == null
              ? null
              : keyFor(entry.value.activeTabId!),
        ),
    },
    activeGroupId: layout.activeGroupId,
  );
}

WorkbenchViewPrefs _prefsWithPanels(Map<String, WorkbenchLayout> layouts) {
  return WorkbenchViewPrefs.defaults.copyWith(
    workspacePanels: <String, WorkspacePanel>{
      for (final entry in layouts.entries)
        entry.key: () {
          final keyed = _panelKeyedLayout(entry.value);
          final focused =
              keyed.activeTabId ?? workspacePanelLayoutKeys(keyed).first;
          return const WorkspacePanel().applyMainLayout(keyed).select(focused);
        }(),
    },
  );
}

WorkbenchState _stackedWorkbenchState() {
  final now = DateTime.utc(2026, 5, 22);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: now,
    updatedAt: now,
  );
  final workspace = Workspace(
    id: 'workspace-1',
    projectId: project.id,
    name: 'Main',
    branch: 'main',
    path: project.repoPath,
    createdAt: now,
    updatedAt: now,
    kind: .main,
    status: .active,
  );
  final firstTab = WorkspaceTabRecord(
    id: 'tab-1',
    workspaceId: workspace.id,
    title: 'Terminal 1',
    createdAt: now,
    updatedAt: now,
  );
  final secondTab = WorkspaceTabRecord(
    id: 'tab-2',
    workspaceId: workspace.id,
    title: 'Terminal 2',
    createdAt: now,
    updatedAt: now,
  );
  return WorkbenchState(
    projects: <Project>[project],
    workspacesByProject: <String, List<Workspace>>{
      project.id: <Workspace>[workspace],
    },
    tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
      workspace.id: <WorkspaceTabRecord>[firstTab, secondTab],
    },
    layoutByWorkspace: <String, WorkbenchLayout>{
      workspace.id: WorkbenchLayout.single(
        workspaceId: workspace.id,
        tabIds: <String>[firstTab.id, secondTab.id],
      ),
    },
    activeProjectId: project.id,
    activeWorkspaceId: workspace.id,
    activeTabIdByWorkspace: <String, String>{workspace.id: secondTab.id},
    viewPrefs: _prefsWithPanels(<String, WorkbenchLayout>{
      workspace.id: WorkbenchLayout.single(
        workspaceId: workspace.id,
        tabIds: <String>[firstTab.id, secondTab.id],
      ),
    }),
    bootstrapped: true,
  );
}

WorkbenchState _populatedWorkbenchState() {
  final now = DateTime.utc(2026, 5, 22);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: now,
    updatedAt: now,
  );
  final workspace = Workspace(
    id: 'workspace-1',
    projectId: project.id,
    name: 'Main',
    branch: 'main',
    path: project.repoPath,
    createdAt: now,
    updatedAt: now,
    kind: .main,
    status: .active,
  );
  final tab = WorkspaceTabRecord(
    id: 'tab-1',
    workspaceId: workspace.id,
    title: 'Terminal 1',
    createdAt: now,
    updatedAt: now,
  );
  return WorkbenchState(
    projects: <Project>[project],
    workspacesByProject: <String, List<Workspace>>{
      project.id: <Workspace>[workspace],
    },
    tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
      workspace.id: <WorkspaceTabRecord>[tab],
    },
    activeProjectId: project.id,
    activeWorkspaceId: workspace.id,
    activeTabIdByWorkspace: <String, String>{workspace.id: tab.id},
    layoutByWorkspace: <String, WorkbenchLayout>{
      workspace.id: WorkbenchLayout.single(
        workspaceId: workspace.id,
        tabIds: <String>[tab.id],
      ),
    },
    viewPrefs: _prefsWithPanels(<String, WorkbenchLayout>{
      workspace.id: WorkbenchLayout.single(
        workspaceId: workspace.id,
        tabIds: <String>[tab.id],
      ),
    }),
    bootstrapped: true,
  );
}

/// One terminal tab plus an unstaged-file diff tab, with the diff active: the
/// shape the workbench has right after a Source Control file is clicked.
WorkbenchState _diffTabWorkbenchState() {
  final base = _populatedWorkbenchState();
  final workspace = base.activeWorkspace!;
  final now = DateTime.utc(2026, 5, 22);
  final diffTab = WorkspaceTabRecord(
    id: 'tab-2',
    workspaceId: workspace.id,
    kind: .gitDiff,
    title: 'main.dart unstaged',
    createdAt: now,
    updatedAt: now,
    payload: <String, Object?>{
      workspaceTabGitDiffSourcePayloadKey:
          WorkspaceGitDiffSource.workingTree.key,
      workspaceTabGitDiffScopePayloadKey: WorkspaceGitDiffScope.file.key,
      workspaceTabFilePathPayloadKey: 'lib/main.dart',
      workspaceTabGitDiffAreaPayloadKey: GitChangeArea.unstaged.key,
    },
  );
  final tabs = <WorkspaceTabRecord>[...base.tabsFor(workspace.id), diffTab];
  final layout = WorkbenchLayout.single(
    workspaceId: workspace.id,
    tabIds: <String>[for (final tab in tabs) tab.id],
  );
  return base.copyWith(
    tabsByWorkspace: <String, List<WorkspaceTabRecord>>{workspace.id: tabs},
    activeTabIdByWorkspace: <String, String>{workspace.id: diffTab.id},
    layoutByWorkspace: <String, WorkbenchLayout>{workspace.id: layout},
    viewPrefs: _prefsWithPanels(<String, WorkbenchLayout>{
      workspace.id: layout,
    }),
  );
}

WorkbenchState _splitWorkbenchState() {
  final now = DateTime.utc(2026, 5, 22);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: now,
    updatedAt: now,
  );
  final workspace = Workspace(
    id: 'workspace-1',
    projectId: project.id,
    name: 'Main',
    branch: 'main',
    path: project.repoPath,
    createdAt: now,
    updatedAt: now,
    kind: .main,
    status: .active,
  );
  final firstTab = WorkspaceTabRecord(
    id: 'tab-1',
    workspaceId: workspace.id,
    title: 'Terminal 1',
    createdAt: now,
    updatedAt: now,
  );
  final secondTab = WorkspaceTabRecord(
    id: 'tab-2',
    workspaceId: workspace.id,
    title: 'Terminal 2',
    createdAt: now,
    updatedAt: now,
  );
  final layout =
      WorkbenchLayout.single(
        workspaceId: workspace.id,
        tabIds: <String>[firstTab.id],
      ).splitWithGroup(
        targetGroupId: WorkbenchLayout.defaultGroupId(workspace.id),
        zone: .right,
        newGroup: WorkbenchPaneGroup(
          id: 'group-2',
          tabIds: <String>[secondTab.id],
          activeTabId: secondTab.id,
        ),
      );
  return WorkbenchState(
    projects: <Project>[project],
    workspacesByProject: <String, List<Workspace>>{
      project.id: <Workspace>[workspace],
    },
    tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
      workspace.id: <WorkspaceTabRecord>[firstTab, secondTab],
    },
    layoutByWorkspace: <String, WorkbenchLayout>{workspace.id: layout},
    activeProjectId: project.id,
    activeWorkspaceId: workspace.id,
    activeTabIdByWorkspace: <String, String>{workspace.id: secondTab.id},
    viewPrefs: _prefsWithPanels(<String, WorkbenchLayout>{
      workspace.id: layout,
    }),
    bootstrapped: true,
  );
}

WorkbenchState _linkedWorkbenchState({
  bool linkedExpanded = false,
  bool linkedActive = false,
}) {
  final now = DateTime.utc(2026, 5, 22);
  final project = Project(
    id: 'project-1',
    name: 'Alera',
    repoPath: '/repo/alera',
    createdAt: now,
    updatedAt: now,
  );
  final mainWorkspace = Workspace(
    id: 'workspace-1',
    projectId: project.id,
    name: 'Main',
    branch: 'main',
    path: project.repoPath,
    createdAt: now,
    updatedAt: now,
    kind: .main,
    status: .active,
  );
  final linkedWorkspace = Workspace(
    id: 'workspace-2',
    projectId: project.id,
    name: 'Feature login',
    branch: 'feature/login',
    sourceBranch: 'main',
    path: '/repo/alera-feature-login',
    createdAt: now,
    updatedAt: now,
    kind: .linked,
    status: .active,
  );
  final mainTab = WorkspaceTabRecord(
    id: 'tab-1',
    workspaceId: mainWorkspace.id,
    title: 'Main terminal',
    createdAt: now,
    updatedAt: now,
  );
  final linkedTab = WorkspaceTabRecord(
    id: 'tab-2',
    workspaceId: linkedWorkspace.id,
    title: 'Linked terminal',
    createdAt: now,
    updatedAt: now,
  );
  final activeWorkspace = linkedActive ? linkedWorkspace : mainWorkspace;
  final expandedWorkspaceIds = <String>{mainWorkspace.id};
  if (linkedExpanded) {
    expandedWorkspaceIds.add(linkedWorkspace.id);
  }
  return WorkbenchState(
    projects: <Project>[project],
    workspacesByProject: <String, List<Workspace>>{
      project.id: <Workspace>[mainWorkspace, linkedWorkspace],
    },
    tabsByWorkspace: <String, List<WorkspaceTabRecord>>{
      mainWorkspace.id: <WorkspaceTabRecord>[mainTab],
      linkedWorkspace.id: <WorkspaceTabRecord>[linkedTab],
    },
    activeProjectId: project.id,
    activeWorkspaceId: activeWorkspace.id,
    activeTabIdByWorkspace: <String, String>{
      mainWorkspace.id: mainTab.id,
      linkedWorkspace.id: linkedTab.id,
    },
    layoutByWorkspace: <String, WorkbenchLayout>{
      mainWorkspace.id: WorkbenchLayout.single(
        workspaceId: mainWorkspace.id,
        tabIds: <String>[mainTab.id],
      ),
      linkedWorkspace.id: WorkbenchLayout.single(
        workspaceId: linkedWorkspace.id,
        tabIds: <String>[linkedTab.id],
      ),
    },
    viewPrefs: _prefsWithPanels(<String, WorkbenchLayout>{
      mainWorkspace.id: WorkbenchLayout.single(
        workspaceId: mainWorkspace.id,
        tabIds: <String>[mainTab.id],
      ),
      linkedWorkspace.id: WorkbenchLayout.single(
        workspaceId: linkedWorkspace.id,
        tabIds: <String>[linkedTab.id],
      ),
    }).copyWith(expandedWorkspaceIds: expandedWorkspaceIds),
    bootstrapped: true,
  );
}

/// Keeps original tabs in the right pane. Reconcile would otherwise adopt the
/// first terminal as the hidden primary and hide agent rows / pane chrome.
WorkbenchState _withSidebarAgentRows(WorkbenchState state) {
  final nextTabs = <String, List<WorkspaceTabRecord>>{...state.tabsByWorkspace};
  final nextPanels = <String, WorkspacePanel>{
    ...state.viewPrefs.workspacePanels,
  };
  final now = DateTime.utc(2026, 5, 22);
  for (final workspaceId in nextTabs.keys) {
    final tabs = nextTabs[workspaceId]!;
    if (tabs.isEmpty || tabs.any((tab) => tab.id == '$workspaceId-primary')) {
      continue;
    }
    final dummy = WorkspaceTabRecord(
      id: '$workspaceId-primary',
      workspaceId: workspaceId,
      title: 'Primary terminal',
      createdAt: now,
      updatedAt: now,
    );
    final all = <WorkspaceTabRecord>[dummy, ...tabs];
    nextTabs[workspaceId] = all;
    final existing = nextPanels[workspaceId] ?? const WorkspacePanel();
    nextPanels[workspaceId] = existing
        .applyMainLayout(
          WorkbenchLayout.single(
            workspaceId: workspaceId,
            tabIds: <String>[WorkspacePanel.tabKey(dummy.id)],
            groupId: '$workspaceId/${WorkspacePanel.mainLayoutGroupSuffix}',
          ),
        )
        .reconcile(all, preferredPrimaryId: dummy.id, workspaceId: workspaceId);
  }
  return state.copyWith(
    tabsByWorkspace: nextTabs,
    viewPrefs: state.viewPrefs.copyWith(workspacePanels: nextPanels),
  );
}

AgentStatusEntry _agentStatusEntry({
  required String terminalSessionId,
  required String workspaceId,
  required String tabId,
  required AgentStatusState state,
  String prompt = '',
  String? toolName,
  String? toolInput,
  String? lastAssistantMessage,
  bool? interrupted,
}) {
  return AgentStatusEntry(
    terminalSessionId: terminalSessionId,
    workspaceId: workspaceId,
    tabId: tabId,
    agentType: .codex,
    state: state,
    prompt: prompt,
    toolName: toolName,
    toolInput: toolInput,
    lastAssistantMessage: lastAssistantMessage,
    interrupted: interrupted,
    updatedAt: .utc(2026, 5, 22),
    stateStartedAt: .utc(2026, 5, 22),
  );
}
