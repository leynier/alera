part of 'workbench_providers.dart';

@Riverpod(keepAlive: true)
void terminalHostWarmupCoordinator(Ref ref) {
  final client = ref.watch(terminalHostClientProvider);
  final runtimeClient = ref.watch(runtimeHostClientProvider);
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
        .then<void>((_) async {
          await runtimeClient.probeRuntimeStatus();
        })
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
    terminalSessionCleanup: (terminalSessionId) {
      // A terminal closed mid-turn never emits the Codex Stop hook, so the
      // transcript watch has to be dropped here or its file poller outlives
      // the session.
      ref
          .read(agentHookReceiverProvider)
          .clearTerminalSession(terminalSessionId);
      return agentRuntimeOverlay.clearTerminalOverlays(terminalSessionId);
    },
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
  final foreground = ref.watch(appForegroundProvider);
  runtime.setAppForeground(foreground.isForeground);
  final foregroundSub = foreground.changes.listen(runtime.setAppForeground);
  ref.onDispose(() {
    unawaited(foregroundSub.cancel());
    runtime.dispose();
  });
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
      if (event.autoCloseOnSuccess && event.exitCode != 0) {
        return;
      }
      // The controller disposes the terminal handle alongside the tab record.
      await ref
          .read(workbenchControllerProvider.notifier)
          .closeWorkspaceTab(workspace: workspace, tabId: event.tabId);
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
  Logger('WorkbenchProviders')
      .warning('background provider work failed', error, stackTrace);
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
