import 'dart:async';
import 'dart:io' show Platform;

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/application/agent_status_providers.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/command_terminal/domain/command_terminal_request.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/projects/application/project_providers.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/terminal_host_settings_config.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_listing.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workbench_view_prefs_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_activity_controller.dart';
import 'package:alera/src/features/workbench/application/workspace_activity_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_explorer_session_store.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/application/workspace_graph_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_search_service.dart';
import 'package:alera/src/features/workbench/infra/runtime_workspace_search_client.dart';
import 'package:alera/src/features/workbench/application/retired_workspace_invalidation.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/application/workspace_tab_service.dart';
import 'package:alera/src/features/workbench/application/worktree_setup_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/drift_workbench_view_prefs_repository.dart';
import 'package:alera/src/features/workbench/infra/drift_workspace_activity_repository.dart';
import 'package:alera/src/features/workbench/infra/runtime_workspace_activity_repository.dart';
import 'package:alera/src/features/workbench/infra/runtime_workbench_view_prefs_repository.dart';
import 'package:alera/src/features/workbench/infra/alera_cli_terminal_shim.dart';
import 'package:alera/src/features/workbench/infra/runtime_managed_workspace_client.dart';
import 'package:alera/src/features/workbench/infra/runtime_workspace_files_client.dart';
import 'package:alera/src/features/workbench/infra/runtime_workspace_graph_repository.dart';
import 'package:alera/src/features/workbench/infra/runtime_workbench_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_pty_session.dart';
import 'package:alera/src/features/workbench/infra/terminal_shell_startup_preparer.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/features/workbench/presentation/workbench_pane_focus_registry.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/process/process_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_state_migration.dart';
import 'package:alera/src/shared/infra/storage/storage_providers.dart';
import 'package:alera/src/shared/infra/uri/uri_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workbench_providers.g.dart';
part 'workbench_provider_coordinators.dart';

@Riverpod(keepAlive: true)
WorkbenchRepository workbenchRepository(Ref ref) {
  return RuntimeWorkbenchRepository(
    ref.watch(runtimeHostClientProvider),
    beforeAccess: ref.watch(runtimeStateMigrationProvider).ensureMigrated,
    coalescer: ref.watch(runtimeChangeCoalescerProvider),
  );
}

@Riverpod(keepAlive: true)
WorkspaceGraphRepository workspaceGraphRepository(Ref ref) {
  return RuntimeWorkspaceGraphRepository(
    ref.watch(runtimeHostClientProvider),
    beforeAccess: ref.watch(runtimeStateMigrationProvider).ensureMigrated,
  );
}

@Riverpod(keepAlive: true)
WorkbenchViewPrefsRepository workbenchViewPrefsRepository(Ref ref) {
  final dbAsync = ref.watch(aleraDatabaseProvider);
  final db = dbAsync.requireValue;
  return RuntimeWorkbenchViewPrefsRepository(
    client: ref.watch(runtimeHostClientProvider),
    legacyRepository: DriftWorkbenchViewPrefsRepository(db),
    beforeAccess: ref.watch(runtimeStateMigrationProvider).ensureMigrated,
  );
}

/// The sidebar row list, recomputed once per state change instead of once per
/// widget rebuild. Filtering and sorting stay out of widget build methods.
@Riverpod(keepAlive: true)
List<WorkbenchSidebarRow> workbenchSidebarRows(Ref ref) {
  final state = ref.watch(
    workbenchControllerProvider.select(
      (state) => (
        sections: state.sections,
        projects: state.projects,
        searchQuery: state.searchQuery,
        tabsByWorkspace: state.tabsByWorkspace,
        viewPrefs: state.viewPrefs,
        workspacesByProject: state.workspacesByProject,
      ),
    ),
  );
  return buildSidebarRows(
    WorkbenchState(
      sections: state.sections,
      projects: state.projects,
      workspacesByProject: state.workspacesByProject,
      tabsByWorkspace: state.tabsByWorkspace,
      viewPrefs: state.viewPrefs,
      searchQuery: state.searchQuery,
    ),
    agentStatuses: ref.watch(agentStatusControllerProvider),
    lastActivityByWorkspaceId: ref.watch(workspaceActivityControllerProvider),
  );
}

/// Focus handles for the mounted workbench surfaces, so keyboard shortcuts can
/// move focus between panes without a pointer.
@Riverpod(keepAlive: true)
WorkbenchPaneFocusRegistry workbenchPaneFocusRegistry(Ref ref) {
  return WorkbenchPaneFocusRegistry();
}

/// Rechecks the terminal memory budget when the active workspace changes.
@Riverpod(keepAlive: true)
void terminalRuntimeActiveWorkspaceCoordinator(Ref ref) {
  final runtime = ref.watch(terminalRuntimeProvider);
  ref.listen<String?>(
    workbenchControllerProvider.select((state) => state.activeWorkspaceId),
    (previous, next) => runtime.setActiveWorkspace(next),
    fireImmediately: true,
  );
}

@Riverpod(keepAlive: true)
WorkspaceExplorerSessionStore workspaceExplorerSessionStore(Ref ref) {
  return WorkspaceExplorerSessionStore();
}

@Riverpod(keepAlive: true)
WorkspaceActivityRepository workspaceActivityRepository(Ref ref) {
  final dbAsync = ref.watch(aleraDatabaseProvider);
  final db = dbAsync.requireValue;
  return RuntimeWorkspaceActivityRepository(
    client: ref.watch(runtimeHostClientProvider),
    legacyRepository: DriftWorkspaceActivityRepository(db),
    beforeAccess: ref.watch(runtimeStateMigrationProvider).ensureMigrated,
  );
}

/// Seeds [WorkspaceActivityController] from shared runtime state, merging the
/// legacy Drift timestamps during migration.
@Riverpod(keepAlive: true)
void workspaceActivityPersistenceCoordinator(Ref ref) {
  final repository = ref.watch(workspaceActivityRepositoryProvider);
  unawaited(
    ref
        .read(workspaceActivityControllerProvider.notifier)
        .attachRepository(repository)
        .catchError((_) {}),
  );
}

@Riverpod(keepAlive: true)
WorkspaceTabService workspaceTabService(Ref ref) {
  return WorkspaceTabService(
    repository: ref.watch(workbenchRepositoryProvider),
  );
}

@Riverpod(keepAlive: true)
WorkspaceFileService workspaceFileService(Ref ref) {
  return WorkspaceFileService(
    remoteFiles: RuntimeWorkspaceFilesClient(
      ref.watch(runtimeHostClientProvider),
      beforeAccess: ref.watch(runtimeStateMigrationProvider).ensureMigrated,
    ),
  );
}

@Riverpod(keepAlive: true)
WorkspaceSearchService workspaceSearchService(Ref ref) {
  return const WorkspaceSearchService();
}

/// Search for a workspace whose checkout lives on another host: the runtime
/// forwards the request over that host's link. Kept alive because the search
/// controller that reads it is, and released when the workspace is retired so
/// it does not outlive the deleted workspace for the rest of the session.
@Riverpod(keepAlive: true)
WorkspaceSearchService remoteWorkspaceSearchService(
  Ref ref,
  String workspaceId,
) {
  invalidateWhenWorkspaceRetired(ref, workspaceId);
  return RuntimeWorkspaceSearchClient(
    ref.watch(runtimeHostClientProvider),
    workspaceId: workspaceId,
    beforeAccess: ref.watch(runtimeStateMigrationProvider).ensureMigrated,
  );
}

@Riverpod(keepAlive: true)
ManagedWorkspaceRuntime? managedWorkspaceRuntime(Ref ref) {
  return RuntimeManagedWorkspaceClient(
    ref.watch(runtimeHostClientProvider),
    beforeAccess: ref.watch(runtimeStateMigrationProvider).ensureMigrated,
  );
}

@Riverpod(keepAlive: true)
AleraCliTerminalShimService aleraCliTerminalShimService(Ref ref) {
  return AleraCliTerminalShimService();
}

@Riverpod(keepAlive: true)
WorktreeSetupRunner worktreeSetupRunner(Ref ref) {
  return WorktreeSetupService(processRunner: ref.watch(processRunnerProvider));
}

@Riverpod(keepAlive: true)
// Callers listen to this ChangeNotifier. Raw keeps the same type and tells
// riverpod_lint not to treat it as provider state.
Raw<EditorSessionRegistry> editorSessionRegistry(Ref ref) {
  final registry = EditorSessionRegistry();
  ref.onDispose(registry.dispose);
  return registry;
}

@Riverpod(keepAlive: true)
WorkspaceService workspaceService(Ref ref) {
  final override = ref.watch(
    settingsControllerProvider.select((s) => s.general.workspaceDirectory),
  );
  return WorkspaceService(
    repository: ref.watch(workbenchRepositoryProvider),
    projectService: ref.watch(projectServiceProvider),
    gitBackend: ref.watch(gitBackendProvider),
    workspaceRoot: WorkspaceRoot(override: override),
    projectConfigReader: ref.watch(projectConfigServiceProvider),
    worktreeSetupRunner: ref.watch(worktreeSetupRunnerProvider),
    managedRuntime: ref.watch(managedWorkspaceRuntimeProvider),
  );
}

@Riverpod(keepAlive: true)
TerminalHostClient terminalHostClient(Ref ref) {
  final settings = ref.read(settingsControllerProvider);
  final initialConfig = terminalHostConfigFor(
    settings.terminal,
    crashReporting: settings.diagnostics.crashReportingEnabled,
  );
  final client = ref.watch(runtimeHostClientProvider);
  unawaited(
    client.configure(initialConfig).catchError(_ignoreProviderAsyncError),
  );
  // Selected as a record so the comparison stays structural: TerminalHostConfig
  // has no value equality, so selecting it directly would reconfigure the host
  // on every unrelated settings write.
  ref.listen<(TerminalSettings, bool)>(
    settingsControllerProvider.select(
      (settings) =>
          (settings.terminal, settings.diagnostics.crashReportingEnabled),
    ),
    (_, next) {
      unawaited(
        client
            .configure(terminalHostConfigFor(next.$1, crashReporting: next.$2))
            .catchError(_ignoreProviderAsyncError),
      );
    },
  );
  ref.onDispose(client.dispose);
  return client;
}
