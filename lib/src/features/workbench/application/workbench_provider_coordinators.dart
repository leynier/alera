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
      observeTab: (workspaceId, tabId) {
        final tab = ref
            .read(workbenchControllerProvider)
            .tabsFor(workspaceId)
            .where((item) => item.id == tabId)
            .firstOrNull;
        return tab != null &&
            automationTabIsObserved(
              tab.payload,
              tabId,
              ref.read(automationTakenOverTabsProvider),
            );
      },
    ),
    initialSettings: ref.read(settingsControllerProvider).terminal,
    externalUriLauncher: ref.watch(externalUriLauncherProvider),
    shellStartupPreparer: shellStartupPreparer,
    terminalSessionCleanup: (terminalSessionId) =>
        _cleanUpTerminalSession(ref, agentRuntimeOverlay, terminalSessionId),
    terminalProcessCreated: (terminalSessionId) => ref
        .read(agentStatusControllerProvider.notifier)
        .clearTerminal(terminalSessionId),
    interactionNotice: (message, {error = false}) {
      AleraToast.publish(
        message: message,
        tone: error ? AleraToastTone.error : AleraToastTone.info,
        duration: error ? AleraToast.longDuration : const Duration(seconds: 12),
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
  // An exit that arrives while the tab's previous one is still being handled,
  // such as a reopened terminal quitting during the sleep lookup, waits here
  // instead of being dropped.
  final queuedExits = <String, TerminalRuntimeExitEvent>{};
  var disposed = false;
  late final void Function(TerminalRuntimeExitEvent event) handleExit;

  Future<void> closeExitedTerminalTab(TerminalRuntimeExitEvent event) async {
    try {
      if (disposed) {
        return;
      }
      // Taken before any await: a different handle afterwards, or this one
      // running or starting again, means the tab restarted and this exit is
      // stale. A start already under way belongs to the process that exited,
      // and a handle that is merely gone was evicted, not restarted.
      final handle = runtime.peekSession(event.tabId);
      final wasStarting = handle?.isStarting ?? false;
      bool restarted() {
        final current = runtime.peekSession(event.tabId);
        return (current != null && !identical(current, handle)) ||
            (handle != null &&
                (handle.isRunning || (handle.isStarting && !wasStarting)));
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
      final controller = ref.read(workbenchControllerProvider.notifier);
      // Sleep ends the session but keeps the tab for the wake. The host names
      // that cause on the removal, which no later wake can erase.
      final List<String> slept;
      if (event.cause.isWorkspaceSleep) {
        slept = <String>{
          ...?state.sleptTabIdsByWorkspaceId[event.workspaceId],
          event.tabId,
        }.toList(growable: false);
      } else {
        // An older host does not, so its slept list, recorded before the
        // sessions ended, is the only evidence.
        try {
          slept = await controller.sleptTerminalIds(event.workspaceId);
        } catch (_) {
          // Without the host's answer the tab stays, as on any other failure
          // here, but the session is dead either way, so its agent state goes.
          final terminalSessionId = handle?.terminalSessionId;
          if (!disposed && !restarted() && terminalSessionId != null) {
            await _cleanUpTerminalSession(
              ref,
              ref.read(agentRuntimeOverlayServiceProvider),
              terminalSessionId,
            );
          }
          return;
        }
      }
      if (disposed || restarted()) {
        return;
      }
      // Any other terminal of the workspace running, a slept one woken or one
      // opened since, means the user is back in it.
      bool workspaceAwake() => ref
          .read(workbenchControllerProvider)
          .tabsFor(event.workspaceId)
          .any((tab) {
            final other = tab.id == event.tabId
                ? null
                : runtime.peekSession(tab.id);
            return other != null && (other.isRunning || other.isStarting);
          });
      final terminalSessionId = handle?.terminalSessionId;
      if (slept.contains(event.tabId)) {
        // When the workspace woke meanwhile, it stays open and this exited
        // handle stays on screen: releasing a mounted handle would leave its
        // surface on disposed objects. A named sleep cause arrives with no
        // wait, while siblings of the same sleep may still be running, so they
        // are no evidence of a wake.
        if (event.cause.isWorkspaceSleep || !workspaceAwake()) {
          controller.settleSleptTerminal(
            event.workspaceId,
            event.tabId,
            slept,
            sleepId: event.cause.sleepId,
          );
        } else {
          controller.retainExitedHandle(event.workspaceId, event.tabId);
        }
        // Neither path closes the session, so its agent state goes here.
        if (terminalSessionId != null) {
          await _cleanUpTerminalSession(
            ref,
            ref.read(agentRuntimeOverlayServiceProvider),
            terminalSessionId,
          );
        }
        return;
      }
      // On an older host, waking clears the slept list for the whole
      // workspace, so a sleep that ended this session can look like nothing by
      // now. The host never removes a session whose tab the desktop should
      // delete while the workspace is in use: the client that closed it
      // removes the tab too.
      if (event.cause.removedByHost && workspaceAwake()) {
        // The exited handle stays mounted, as above, until the tab closes or
        // the workspace leaves the screen.
        controller.retainExitedHandle(event.workspaceId, event.tabId);
        if (terminalSessionId != null) {
          await _cleanUpTerminalSession(
            ref,
            ref.read(agentRuntimeOverlayServiceProvider),
            terminalSessionId,
          );
        }
        return;
      }
      if (event.autoCloseOnSuccess && event.exitCode != 0) {
        return;
      }
      // The controller disposes the terminal handle alongside the tab record.
      await controller.closeWorkspaceTab(
        workspace: workspace,
        tabId: event.tabId,
      );
    } catch (_) {
      // WorkbenchController records close failures in state; keep the tab so
      // the user is not left with a silently removed terminal on persistence errors.
    } finally {
      closingTabIds.remove(event.tabId);
      final queued = queuedExits.remove(event.tabId);
      final current = runtime.peekSession(event.tabId);
      // A terminal running again has outlived the queued exit, which would
      // otherwise mark its new agent finished.
      if (queued != null &&
          !(current != null && (current.isRunning || current.isStarting))) {
        handleExit(queued);
      }
    }
  }

  handleExit = (event) {
    if (disposed) {
      return;
    }
    if (!closingTabIds.add(event.tabId)) {
      queuedExits[event.tabId] = event;
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
  };

  final subscription = runtime.exits.listen((event) {
    // A command terminal belongs to the dialog that opened it, not to the
    // workbench. Closing its session here would wipe the output the moment the
    // shell exited, which is exactly when the user wants to read it, and would
    // report agent and activity events against a synthetic workspace id.
    if (isCommandTerminalWorkspaceId(event.workspaceId)) {
      return;
    }
    handleExit(event);
  });

  ref.onDispose(() {
    disposed = true;
    unawaited(subscription.cancel());
  });
}

Future<void> _cleanUpTerminalSession(
  Ref ref,
  AgentRuntimeOverlayService agentRuntimeOverlay,
  String terminalSessionId,
) {
  // A terminal closed mid-turn never emits the Codex Stop hook, so the
  // transcript watch has to be dropped here or its file poller outlives the
  // session.
  ref.read(agentHookReceiverProvider).clearTerminalSession(terminalSessionId);
  return agentRuntimeOverlay.clearTerminalOverlays(terminalSessionId);
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
