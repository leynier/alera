import 'dart:async';
import 'dart:io' show Platform;

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/application/agent_status_providers.dart';
import 'package:alera/src/features/browser/infra/runtime_browser_closed_tabs_service.dart';
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
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/application/workspace_graph_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_search_service.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/application/workspace_tab_service.dart';
import 'package:alera/src/features/workbench/application/workspace_browser_tab_service.dart';
import 'package:alera/src/features/workbench/application/worktree_setup_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/drift_workbench_view_prefs_repository.dart';
import 'package:alera/src/features/workbench/infra/drift_workspace_activity_repository.dart';
import 'package:alera/src/features/workbench/infra/runtime_workspace_activity_repository.dart';
import 'package:alera/src/features/workbench/infra/runtime_workbench_view_prefs_repository.dart';
import 'package:alera/src/features/workbench/infra/alera_cli_terminal_shim.dart';
import 'package:alera/src/features/workbench/infra/runtime_managed_workspace_client.dart';
import 'package:alera/src/features/workbench/infra/runtime_workspace_graph_repository.dart';
import 'package:alera/src/features/workbench/infra/runtime_workbench_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_pty_session.dart';
import 'package:alera/src/features/workbench/infra/terminal_shell_startup_preparer.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
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
/// widget rebuild.
///
/// `buildSidebarRows` filters and multi-key sorts every workspace, and the
/// sidebar used to run it inline on every rebuild while also mutating the
/// order memory during build.
@Riverpod(keepAlive: true)
List<WorkbenchSidebarRow> workbenchSidebarRows(Ref ref) {
  final state = ref.watch(
    workbenchControllerProvider.select(
      (state) => (
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

/// Keeps the terminal runtime's pinned workspace in sync with the active one,
/// so the memory budget never evicts a terminal in the workspace being worked
/// in.
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
WorkspaceBrowserTabService workspaceBrowserTabService(Ref ref) {
  return WorkspaceBrowserTabService(
    repository: ref.watch(workbenchRepositoryProvider),
    closedTabsService: RuntimeBrowserClosedTabsService(
      ref.watch(runtimeHostClientProvider),
    ),
  );
}

@Riverpod(keepAlive: true)
WorkspaceFileService workspaceFileService(Ref ref) {
  return const WorkspaceFileService();
}

@Riverpod(keepAlive: true)
WorkspaceSearchService workspaceSearchService(Ref ref) {
  return const WorkspaceSearchService();
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
EditorSessionRegistry editorSessionRegistry(Ref ref) {
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

@Riverpod(keepAlive: true)
void terminalHostWarmupCoordinator(Ref ref) {
  final client = ref.watch(terminalHostClientProvider);
  unawaited(
    client
        .ensureStarted(
          config: terminalHostConfigFor(
            ref.read(settingsControllerProvider).terminal,
            crashReporting: ref
                .read(settingsControllerProvider)
                .diagnostics
                .crashReportingEnabled,
          ),
        )
        .catchError(_ignoreProviderAsyncError),
  );
}

@Riverpod(keepAlive: true)
TerminalRuntime terminalRuntime(Ref ref) {
  final terminalHostClient = ref.watch(terminalHostClientProvider);
  final agentRuntimeOverlay = ref.watch(agentRuntimeOverlayServiceProvider);
  final aleraCliShim = ref.watch(aleraCliTerminalShimServiceProvider);
  final shellStartupPreparer = ref.watch(terminalShellStartupPreparerProvider);
  final runtime = XtermTerminalRuntime(
    ptySessionFactory: TerminalHostPtySessionFactory(
      client: terminalHostClient,
    ),
    initialSettings: ref.read(settingsControllerProvider).terminal,
    externalUriLauncher: ref.watch(externalUriLauncherProvider),
    shellStartupPreparer: shellStartupPreparer,
    terminalSessionCleanup: agentRuntimeOverlay.clearTerminalOverlays,
    terminalProcessCreated: (terminalSessionId) => ref
        .read(agentStatusControllerProvider.notifier)
        .clearTerminal(terminalSessionId),
    interactionNotice: (message, {error = false}) {
      AleraToast.publish(
        message: message,
        tone: error ? AleraToastTone.error : AleraToastTone.info,
        duration: error
            ? const Duration(seconds: 6)
            : const Duration(seconds: 12),
      );
    },
    agentHookEnvironmentBuilder:
        ({required terminalSessionId, required workspaceId, required tabId}) {
          final environment = <String, String>{};
          Future<void> addAleraCliShim() async {
            try {
              _mergeTerminalLaunchEnvironment(
                environment,
                await aleraCliShim.prepareForTerminalLaunch(),
              );
            } catch (_) {}
          }

          return addAleraCliShim().then(
            (_) => environment.isEmpty ? null : environment,
          );
        },
  );
  ref.listen<TerminalSettings>(
    settingsControllerProvider.select((settings) => settings.terminal),
    (_, next) => runtime.updateSettings(next),
  );
  ref.onDispose(runtime.dispose);
  return runtime;
}

@Riverpod(keepAlive: true)
TerminalShellStartupPreparer terminalShellStartupPreparer(Ref ref) {
  return AleraTerminalShellStartupPreparer();
}

@Riverpod(keepAlive: true)
void terminalRuntimeExitCoordinator(Ref ref) {
  final runtime = ref.watch(terminalRuntimeProvider);
  final closingTabIds = <String>{};
  var disposed = false;

  Future<void> closeExitedTerminalTab(TerminalRuntimeExitEvent event) async {
    try {
      if (disposed) {
        return;
      }
      final state = ref.read(workbenchControllerProvider);
      final workspace = findWorkspaceById(state, event.workspaceId);
      final tabStillExists = state
          .tabsFor(event.workspaceId)
          .any((tab) => tab.id == event.tabId);
      if (workspace == null || !tabStillExists) {
        runtime.closeTab(event.tabId);
        return;
      }
      await ref
          .read(workbenchControllerProvider.notifier)
          .closeWorkspaceTab(workspace: workspace, tabId: event.tabId);
      runtime.closeTab(event.tabId);
    } catch (_) {
      // WorkbenchController records close failures in state; keep the tab so
      // the user is not left with a silently removed terminal on persistence errors.
    } finally {
      closingTabIds.remove(event.tabId);
    }
  }

  final subscription = runtime.exits.listen((event) {
    // A command terminal belongs to the dialog that opened it, not to the
    // workbench. Closing its session here would wipe the output the moment the
    // shell exited, which is exactly when the user wants to read it, and would
    // report agent and activity events against a synthetic workspace id.
    if (isCommandTerminalWorkspaceId(event.workspaceId)) {
      return;
    }
    if (disposed || !closingTabIds.add(event.tabId)) {
      return;
    }
    ref
        .read(agentStatusControllerProvider.notifier)
        .markTerminalExited(
          workspaceId: event.workspaceId,
          tabId: event.tabId,
          exitCode: event.exitCode,
        );
    ref
        .read(workspaceActivityControllerProvider.notifier)
        .recordActivity(event.workspaceId, DateTime.now().toUtc());
    unawaited(closeExitedTerminalTab(event));
  });

  ref.onDispose(() {
    disposed = true;
    unawaited(subscription.cancel());
  });
}

Workspace? findWorkspaceById(WorkbenchState state, String workspaceId) {
  for (final workspaces in state.workspacesByProject.values) {
    for (final workspace in workspaces) {
      if (workspace.id == workspaceId) {
        return workspace;
      }
    }
  }
  return null;
}

Project? findProjectById(WorkbenchState state, String projectId) {
  for (final project in state.projects) {
    if (project.id == projectId) {
      return project;
    }
  }
  return null;
}

WorkspaceTabRecord? findTabById(
  WorkbenchState state,
  String workspaceId,
  String tabId,
) {
  for (final tab in state.tabsFor(workspaceId)) {
    if (tab.id == tabId) {
      return tab;
    }
  }
  return null;
}

// coverage:ignore-start
/// Absorbs a failure from provider work started without awaiting it.
///
/// These must not surface as uncaught zone errors, but discarding them left the
/// workbench with no explanation for a host that never configured or a terminal
/// that never warmed up. Recorded at warning level rather than severe: the app
/// keeps working, it is the follow-up work that did not happen.
void _ignoreProviderAsyncError(Object error, StackTrace stackTrace) {
  Logger(
    'WorkbenchProviders',
  ).warning('background provider work failed', error, stackTrace);
}
// coverage:ignore-end

/// Joins path-list environment values (PATH-style), not filesystem path segments.
///
/// `ALERA_AGENT_WRAPPER_PATH` holds one or more wrapper *directories* separated
/// by `:` on POSIX and `;` on Windows. Using [Platform.pathSeparator] (`/` or
/// `\`) would split absolute paths into garbage fragments and drop the Amp /
/// Cursor wrappers from PATH, so status plugins never load.
@visibleForTesting
void mergeTerminalLaunchEnvironmentForTesting(
  Map<String, String> target,
  Map<String, String>? source,
) {
  _mergeTerminalLaunchEnvironment(target, source);
}

void _mergeTerminalLaunchEnvironment(
  Map<String, String> target,
  Map<String, String>? source,
) {
  if (source == null || source.isEmpty) {
    return;
  }
  final wrapperEntries = <String>[
    ..._splitPathList(target['ALERA_AGENT_WRAPPER_PATH']),
    ..._splitPathList(source['ALERA_AGENT_WRAPPER_PATH']),
  ];
  target.addAll(source);
  if (wrapperEntries.isEmpty) {
    target.remove('ALERA_AGENT_WRAPPER_PATH');
    return;
  }
  final seen = <String>{};
  target['ALERA_AGENT_WRAPPER_PATH'] = wrapperEntries
      .where((entry) => entry.isNotEmpty && seen.add(entry))
      .join(_pathListSeparator);
}

List<String> _splitPathList(String? value) {
  if (value == null || value.isEmpty) {
    return const <String>[];
  }
  return value
      .split(_pathListSeparator)
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

String get _pathListSeparator => Platform.isWindows ? ';' : ':';
