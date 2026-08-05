import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_quota/domain/agent_quota.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/shell/presentation/alera_shell_page.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/application/workspace_folder_opener.dart';
import 'package:alera/src/features/workbench/application/workspace_graph_repository.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/domain/workbench_layout.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/widgets/agent_run_spinner_scope.dart';
import 'package:alera/src/features/workbench/presentation/project_workbench_sidebar.dart';
import 'package:alera/src/features/workbench/presentation/widgets/workspace_agent_compact_summary.dart';
import 'package:alera/src/features/workbench/presentation/workspace_workbench_view.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

part 'alera_shell_page_test_harness.dart';
part 'alera_shell_page_runtime_test_harness.dart';
part 'alera_shell_page_workbench_test_cases.dart';
part 'alera_shell_page_codex_sidebar_test_cases.dart';
part 'alera_shell_page_sidebar_actions_test_cases.dart';
part 'alera_shell_page_sidebar_states_test_cases.dart';
part 'alera_shell_page_pinning_test_cases.dart';
part 'alera_shell_page_sidebar_identity_test_cases.dart';

Future<AleraDatabase> _openMemoryDb() async {
  return AleraDatabase(executor: NativeDatabase.memory());
}

Future<_ShellPumpHarness> _pumpShell(
  WidgetTester tester, {
  required WorkbenchState state,
  _FakeTerminalRuntime? terminalRuntime,
  WorkspaceFolderOpener? workspaceFolderOpener,
  _ShellTestWorkbenchController? controller,
  EditorSessionRegistry? editorSessionRegistry,
  AleraSettings? settings,
  Map<String, AgentStatusEntry> agentStatuses =
      const <String, AgentStatusEntry>{},
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
        terminalRuntimeProvider.overrideWith((ref) => runtime),
        if (editorSessionRegistry != null)
          editorSessionRegistryProvider.overrideWithValue(
            editorSessionRegistry,
          ),
        terminalHostWarmupCoordinatorProvider.overrideWith((ref) {}),
        settingsControllerProvider.overrideWith(() => settingsController),
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
  _registerAleraShellCodexSidebarTests();
  _registerAleraShellSidebarActionTests();
  _registerAleraShellSidebarStateTests();
  _registerAleraShellPinningTests();
  _registerAleraShellSidebarIdentityTests();
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
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
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
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
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
    bootstrapped: true,
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
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
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
        zone: WorkbenchDropZone.right,
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
    kind: WorkspaceKind.main,
    status: WorkspaceStatus.active,
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
    kind: WorkspaceKind.linked,
    status: WorkspaceStatus.active,
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
    viewPrefs: WorkbenchViewPrefs.defaults.copyWith(
      expandedWorkspaceIds: expandedWorkspaceIds,
    ),
    bootstrapped: true,
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
    agentType: AgentType.codex,
    state: state,
    prompt: prompt,
    toolName: toolName,
    toolInput: toolInput,
    lastAssistantMessage: lastAssistantMessage,
    interrupted: interrupted,
    updatedAt: DateTime.utc(2026, 5, 22),
    stateStartedAt: DateTime.utc(2026, 5, 22),
  );
}
