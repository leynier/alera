part of 'providers.dart';

final terminalRuntimeProvider = Provider<TerminalRuntime>((ref) {
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
          return _terminalLaunchEnvironmentFor(
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
  ref.onDispose(() {
    runtime.dispose();
  });
  return runtime;
});

final terminalShellStartupPreparerProvider =
    Provider<TerminalShellStartupPreparer>((ref) {
      return AleraTerminalShellStartupPreparer();
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

Project? _findProjectById(WorkbenchState state, String projectId) {
  for (final project in state.projects) {
    if (project.id == projectId) {
      return project;
    }
  }
  return null;
}

WorkspaceTabRecord? _findTabById(
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
