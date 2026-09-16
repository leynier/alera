import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/ai_assist/application/agent_title_providers.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_quota/domain/agent_quota.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/remote_hosts/application/ssh_target_providers.dart';
import 'package:alera/src/features/remote_hosts/infra/runtime_ssh_target_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/shell/presentation/alera_shell_page.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/application/workspace_folder_opener.dart';
import 'package:alera/src/features/workbench/application/workspace_graph_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/application/workspace_removal_dependencies.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace_panel.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_section.dart';
import 'package:alera/src/features/workbench/domain/workspace_creation_result.dart';
import 'package:alera/src/features/workbench/domain/workspace_hand_on_result.dart';
import 'package:alera/src/features/workbench/domain/workspace_storage_impact.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/widgets/agent_run_spinner_scope.dart';
import 'package:alera/src/features/workbench/presentation/project_workbench_sidebar.dart';
import 'package:alera/src/features/workbench/presentation/widgets/workspace_agent_compact_summary.dart';
import 'package:alera/src/features/workbench/presentation/workspace_panel_view.dart';
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../unit/fake_git_backend.dart';

part 'alera_shell_page_test_harness.dart';
part 'alera_shell_page_runtime_test_harness.dart';
part 'alera_shell_page_workbench_test_cases.dart';
part 'alera_shell_page_shortcut_test_cases.dart';
part 'alera_shell_page_sidebar_actions_test_cases.dart';
part 'alera_shell_page_sidebar_mutation_test_cases.dart';
part 'alera_shell_page_sidebar_states_test_cases.dart';
part 'alera_shell_page_workspace_removal_test_cases.dart';
part 'alera_shell_page_sidebar_titles_test_cases.dart';
part 'alera_shell_page_pinning_test_cases.dart';
part 'alera_shell_page_section_menu_test_cases.dart';
part 'alera_shell_page_project_removal_test_cases.dart';
part 'alera_shell_page_sidebar_identity_test_cases.dart';

Future<AleraDatabase> _openMemoryDb() async {
  return AleraDatabase(executor: NativeDatabase.memory());
}

Future<_ShellPumpHarness> _pumpShell(
  WidgetTester tester, {
  required WorkbenchState state,
  _FakeTerminalRuntime? terminalRuntime,
  _FakeManagedWorkspaceRuntime? managedRuntime,
  WorkspaceFolderOpener? workspaceFolderOpener,
  _ShellTestWorkbenchController? controller,
  EditorSessionRegistry? editorSessionRegistry,
  GitBackend? gitBackend,
  AleraSettings? settings,
  Map<String, AgentStatusEntry> agentStatuses =
      const <String, AgentStatusEntry>{},
  bool agentTitlesAvailable = false,
}) async {
  final shellController = controller ?? _ShellTestWorkbenchController(state);
  final runtime = terminalRuntime ?? _FakeTerminalRuntime();
  final settingsController = _ShellSettingsController(
    settings ?? AleraSettings.defaults,
  );
  final agentStatusController = _ShellTestAgentStatusController(agentStatuses);
  final db = await _openMemoryDb();
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        aleraDatabaseProvider.overrideWith((ref) async => db),
        workbenchControllerProvider.overrideWith(() => shellController),
        agentProfilesProvider.overrideWith(() => _ShellAgentProfiles()),
        agentStatusControllerProvider.overrideWith(() => agentStatusController),
        agentQuotaStateProvider.overrideWith(
          (ref) async =>
              AgentQuotaState.empty(state.activeWorkspace?.hostId ?? 'local'),
        ),
        managedWorkspaceRuntimeProvider.overrideWithValue(
          managedRuntime ?? const _FakeManagedWorkspaceRuntime(),
        ),
        sshTargetRepositoryProvider.overrideWithValue(
          RuntimeSshTargetRepository(_ShellRuntimeHostClient()),
        ),
        terminalRuntimeProvider.overrideWith((ref) => runtime),
        if (editorSessionRegistry != null)
          editorSessionRegistryProvider.overrideWithValue(
            editorSessionRegistry,
          ),
        if (gitBackend != null)
          gitBackendProvider.overrideWithValue(gitBackend),
        terminalHostWarmupCoordinatorProvider.overrideWith((ref) {}),
        settingsControllerProvider.overrideWith(() => settingsController),
        agentTitleAvailableProvider.overrideWith(
          (ref) async => agentTitlesAvailable,
        ),
        if (workspaceFolderOpener != null)
          workspaceFolderOpenerProvider.overrideWith(
            (ref) => workspaceFolderOpener,
          ),
      ],
      child: MaterialApp(
        home: AleraShellPage(key: const ValueKey<String>('alera-shell-page')),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  return _ShellPumpHarness(
    controller: shellController,
    runtime: runtime,
    agentStatus: agentStatusController,
  );
}

class _ShellAgentProfiles extends AgentProfiles {
  @override
  Future<List<AgentProfile>> build() async => const <AgentProfile>[];
}

void main() {
  _registerAleraShellWorkbenchTests();
  _registerAleraShellShortcutTests();
  _registerAleraShellSidebarActionTests();
  _registerProjectRemovalDependencyTests();
  _registerAleraShellSidebarMutationTests();
  _registerAleraShellSidebarStateTests();
  _registerAleraShellWorkspaceRemovalTests();
  _registerAleraShellSidebarTitleTests();
  _registerAleraShellPinningTests();
  _registerAleraShellSectionMenuTests();
  _registerAleraShellSidebarIdentityTests();
}

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
