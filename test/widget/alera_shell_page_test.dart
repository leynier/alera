import 'dart:async';

import 'package:code_forge/code_forge.dart' as code_forge;
import 'package:alera/src/features/orchestration/application/run_board_navigation.dart';
import 'package:alera/src/features/orchestration/application/run_board_providers.dart';
import 'package:alera/src/features/orchestration/presentation/run_board_page.dart';
import 'package:alera/src/features/workbench/presentation/workspace_editor_surface.dart';

import '../support/run_board_fixtures.dart';
import '../support/run_board_widget_harness.dart';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/icons/alera_linked_worktree_icon.dart';
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
part 'alera_shell_page_fixtures.dart';
part 'alera_shell_page_runtime_test_harness.dart';
part 'alera_shell_page_workbench_test_cases.dart';
part 'alera_shell_page_shortcut_test_cases.dart';
part 'alera_shell_page_sidebar_actions_test_cases.dart';
part 'alera_shell_page_sidebar_mutation_test_cases.dart';
part 'alera_shell_page_sidebar_states_test_cases.dart';
part 'alera_shell_page_workspace_tray_test_cases.dart';
part 'alera_shell_page_run_board_test_cases.dart';
part 'alera_shell_page_sidebar_worktree_role_test_cases.dart';
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
  BoardTestRepository? boardRepository,
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
        if (boardRepository != null)
          runBoardRepositoryProvider.overrideWithValue(boardRepository),
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
  _registerAleraShellWorkspaceTrayTests();
  _registerAleraShellRunBoardTests();
  _registerAleraShellSidebarWorktreeRoleTests();
  _registerAleraShellWorkspaceRemovalTests();
  _registerAleraShellSidebarTitleTests();
  _registerAleraShellPinningTests();
  _registerAleraShellSectionMenuTests();
  _registerAleraShellSidebarIdentityTests();
}
