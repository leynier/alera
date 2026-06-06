import 'dart:async';

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/application/agent_status_providers.dart';
import 'package:alera/src/features/projects/application/project_providers.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workbench_view_prefs_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_file_service.dart';
import 'package:alera/src/features/workbench/application/workspace_search_service.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/application/workspace_tab_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/drift_workbench_repository.dart';
import 'package:alera/src/features/workbench/infra/drift_workbench_view_prefs_repository.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_pty_session.dart';
import 'package:alera/src/features/workbench/infra/terminal_shell_startup_preparer.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/storage/storage_providers.dart';
import 'package:alera/src/shared/infra/uri/uri_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workbench_providers.g.dart';

@Riverpod(keepAlive: true)
WorkbenchRepository workbenchRepository(Ref ref) {
  final dbAsync = ref.watch(aleraDatabaseProvider);
  final db = dbAsync.requireValue;
  return DriftWorkbenchRepository(db);
}

@Riverpod(keepAlive: true)
WorkbenchViewPrefsRepository workbenchViewPrefsRepository(Ref ref) {
  final dbAsync = ref.watch(aleraDatabaseProvider);
  final db = dbAsync.requireValue;
  return DriftWorkbenchViewPrefsRepository(db);
}

@Riverpod(keepAlive: true)
WorkspaceTabService workspaceTabService(Ref ref) {
  return WorkspaceTabService(
    repository: ref.watch(workbenchRepositoryProvider),
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
EditorSessionRegistry editorSessionRegistry(Ref ref) {
  return EditorSessionRegistry();
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
  );
}

@Riverpod(keepAlive: true)
TerminalHostClient terminalHostClient(Ref ref) {
  final initialConfig = _terminalHostConfigFor(
    ref.read(settingsControllerProvider).terminal,
  );
  final client = SocketTerminalHostClient(initialConfig: initialConfig);
  ref.listen<TerminalSettings>(
    settingsControllerProvider.select((settings) => settings.terminal),
    (_, next) {
      unawaited(
        client
            .configure(_terminalHostConfigFor(next))
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
          config: _terminalHostConfigFor(
            ref.read(settingsControllerProvider).terminal,
          ),
        )
        .catchError(_ignoreProviderAsyncError),
  );
}

@Riverpod(keepAlive: true)
TerminalRuntime terminalRuntime(Ref ref) {
  final terminalHostClient = ref.watch(terminalHostClientProvider);
  final agentHookReceiver = ref.watch(agentHookReceiverProvider);
  final codexRuntimeHome = ref.watch(codexRuntimeHomeServiceProvider);
  final claudeRuntimeHome = ref.watch(claudeRuntimeHomeServiceProvider);
  final agentRuntimeOverlay = ref.watch(agentRuntimeOverlayServiceProvider);
  final shellStartupPreparer = ref.watch(terminalShellStartupPreparerProvider);
  final runtime = XtermTerminalRuntime(
    ptySessionFactory: TerminalHostPtySessionFactory(
      client: terminalHostClient,
    ),
    initialSettings: ref.read(settingsControllerProvider).terminal,
    externalUriLauncher: ref.watch(externalUriLauncherProvider),
    shellStartupPreparer: shellStartupPreparer,
    terminalSessionCleanup: agentRuntimeOverlay.clearTerminalOverlays,
    agentHookEnvironmentBuilder:
        ({required terminalSessionId, required workspaceId, required tabId}) {
          final hooks = ref
              .read(settingsControllerProvider)
              .general
              .agentStatusHooks;
          if (!hooks.anyEnabled) {
            return null;
          }
          return terminalLaunchEnvironmentFor(
            agentHookReceiver: agentHookReceiver,
            codexRuntimeHome: codexRuntimeHome,
            claudeRuntimeHome: claudeRuntimeHome,
            agentRuntimeOverlay: agentRuntimeOverlay,
            hooks: hooks,
            terminalSessionId: terminalSessionId,
            workspaceId: workspaceId,
            tabId: tabId,
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
    unawaited(closeExitedTerminalTab(event));
  });

  ref.onDispose(() {
    disposed = true;
    unawaited(subscription.cancel());
  });
}

TerminalHostConfig _terminalHostConfigFor(TerminalSettings settings) {
  return TerminalHostConfig(
    emptyShutdownDelaySeconds: settings.hostEmptyShutdownDelaySeconds,
    detachedSessionShutdownDelaySeconds:
        settings.hostDetachedSessionShutdownDelaySeconds,
    scrollbackBytes: settings.hostScrollbackBytes,
  );
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
void _ignoreProviderAsyncError(Object error, StackTrace stackTrace) {}
// coverage:ignore-end
