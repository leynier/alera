import 'dart:async';

import 'package:alera/src/app/dependencies.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/updater/application/update_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_pty_session.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:alera/src/app/dependencies.dart';
export 'package:alera/src/features/settings/application/github_star_controller.dart'
    show GitHubStarController, GitHubStarState, gitHubStarControllerProvider;
export 'package:alera/src/features/settings/application/settings_controller.dart'
    show SettingsController, settingsControllerProvider;
export 'package:alera/src/features/updater/application/update_controller.dart'
    show AleraUpdateController, aleraUpdateControllerProvider;
export 'package:alera/src/features/workbench/application/workbench_controller.dart'
    show WorkbenchController, workbenchControllerProvider;

final workspaceServiceProvider = Provider<WorkspaceService>((ref) {
  final override = ref.watch(
    settingsControllerProvider.select((s) => s.general.workspaceDirectory),
  );
  return WorkspaceService(
    repository: ref.watch(workbenchRepositoryProvider),
    projectService: ref.watch(projectServiceProvider),
    processRunner: ref.watch(processRunnerProvider),
    workspaceRoot: WorkspaceRoot(override: override),
  );
});

final terminalHostClientProvider = Provider<TerminalHostClient>((ref) {
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
});

final terminalHostWarmupProvider = Provider<void>((ref) {
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
});

final terminalRuntimeProvider = Provider<TerminalRuntime>((ref) {
  final terminalHostClient = ref.watch(terminalHostClientProvider);
  final runtime = XtermTerminalRuntime(
    ptySessionFactory: TerminalHostPtySessionFactory(
      client: terminalHostClient,
    ),
    initialSettings: ref.read(settingsControllerProvider).terminal,
    externalUriLauncher: ref.watch(externalUriLauncherProvider),
  );
  ref.listen<TerminalSettings>(
    settingsControllerProvider.select((settings) => settings.terminal),
    (_, next) => runtime.updateSettings(next),
  );
  ref.onDispose(() {
    runtime.dispose();
  });
  return runtime;
});

final terminalRuntimeExitCoordinatorProvider = Provider<void>((ref) {
  final runtime = ref.watch(terminalRuntimeProvider);
  final closingTabIds = <String>{};
  var disposed = false;

  Future<void> closeExitedTerminalTab(TerminalRuntimeExitEvent event) async {
    try {
      if (disposed) {
        return;
      }
      final state = ref.read(workbenchControllerProvider);
      final workspace = _findWorkspaceById(state, event.workspaceId);
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
    unawaited(closeExitedTerminalTab(event));
  });

  ref.onDispose(() {
    disposed = true;
    unawaited(subscription.cancel());
  });
});

final updateControllerProvider = aleraUpdateControllerProvider;

Workspace? _findWorkspaceById(WorkbenchState state, String workspaceId) {
  for (final workspaces in state.workspacesByProject.values) {
    for (final workspace in workspaces) {
      if (workspace.id == workspaceId) {
        return workspace;
      }
    }
  }
  return null;
}

TerminalHostConfig _terminalHostConfigFor(TerminalSettings settings) {
  return TerminalHostConfig(
    emptyShutdownDelaySeconds: settings.hostEmptyShutdownDelaySeconds,
    detachedSessionShutdownDelaySeconds:
        settings.hostDetachedSessionShutdownDelaySeconds,
    scrollbackBytes: settings.hostScrollbackBytes,
  );
}

// coverage:ignore-start
void _ignoreProviderAsyncError(Object error, StackTrace stackTrace) {}
// coverage:ignore-end
