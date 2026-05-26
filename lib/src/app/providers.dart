import 'dart:async';

import 'package:alera/src/app/dependencies.dart';
import 'package:alera/src/features/agent_status/application/agent_status_notification_activation_service.dart';
import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/application/agent_status_notifications.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_receiver.dart';
import 'package:alera/src/features/agent_status/infra/desktop_agent_status_notification_service.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:alera/src/features/agent_status/infra/window_manager_agent_window_activator.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/updater/application/update_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_pty_session.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'package:alera/src/app/dependencies.dart';
export 'package:alera/src/features/agent_status/application/agent_status_controller.dart'
    show
        AgentStatusController,
        agentStatusControllerProvider,
        agentStatusByTerminalSessionProvider;
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

final agentHookReceiverProvider = Provider<AgentHookReceiver>((ref) {
  final receiver = AgentHookReceiver(
    statusSink: ref.read(agentStatusControllerProvider.notifier),
  );
  ref.onDispose(() {
    unawaited(receiver.dispose());
  });
  return receiver;
});

final managedAgentHookInstallServiceProvider =
    Provider<ManagedAgentHookInstallService>((ref) {
      return ManagedAgentHookInstallService();
    });

final agentStatusNotificationPresenterProvider =
    Provider<AgentStatusNotificationPresenter>((ref) {
      return DesktopAgentStatusNotificationService();
    });

final agentNotificationWindowActivatorProvider =
    Provider<AgentNotificationWindowActivator>((ref) {
      return const WindowManagerAgentWindowActivator();
    });

final agentNotificationWorkbenchNavigatorProvider =
    Provider<AgentNotificationWorkbenchNavigator>((ref) {
      return _RiverpodAgentNotificationWorkbenchNavigator(ref);
    });

final agentNotificationTerminalFocusRequesterProvider =
    Provider<AgentNotificationTerminalFocusRequester>((ref) {
      return _RiverpodAgentNotificationTerminalFocusRequester(ref);
    });

final agentStatusNotificationActivationServiceProvider =
    Provider<AgentStatusNotificationActivationService>((ref) {
      return AgentStatusNotificationActivationService(
        windowActivator: ref.watch(agentNotificationWindowActivatorProvider),
        navigator: ref.watch(agentNotificationWorkbenchNavigatorProvider),
        terminalFocusRequester: ref.watch(
          agentNotificationTerminalFocusRequesterProvider,
        ),
      );
    });

final agentHookReceiverLifecycleProvider = Provider<void>((ref) {
  final enabled = ref.watch(
    settingsControllerProvider.select(
      (settings) => settings.general.agentStatusHooksEnabled,
    ),
  );
  final receiver = ref.watch(agentHookReceiverProvider);
  if (enabled) {
    unawaited(receiver.start().catchError(_ignoreProviderAsyncError));
  } else {
    unawaited(receiver.stop().catchError(_ignoreProviderAsyncError));
  }
});

final agentHookInstallerCoordinatorProvider = Provider<void>((ref) {
  final service = ref.watch(managedAgentHookInstallServiceProvider);
  ref.listen<bool>(
    settingsControllerProvider.select(
      (settings) => settings.general.agentStatusHooksEnabled,
    ),
    (previous, next) {
      if (previous == null || previous == next) {
        return;
      }
      final operation = next ? service.installAll() : service.removeAll();
      unawaited(
        operation.then<void>((_) {}).catchError(_ignoreProviderAsyncError),
      );
    },
  );
});

final agentStatusNotificationCoordinatorProvider = Provider<void>((ref) {
  final hooksEnabled = ref.watch(
    settingsControllerProvider.select(
      (settings) => settings.general.agentStatusHooksEnabled,
    ),
  );
  final notificationsEnabled = ref.watch(
    settingsControllerProvider.select(
      (settings) => settings.general.agentStatusNotificationsEnabled,
    ),
  );
  final presenter = ref.watch(agentStatusNotificationPresenterProvider);
  final activationService = ref.watch(
    agentStatusNotificationActivationServiceProvider,
  );
  final tracker = AgentStatusNotificationTracker();
  var initialized = false;
  Future<void>? initializing;

  Future<void> ensureInitialized() async {
    if (initialized) {
      return;
    }
    initializing ??= presenter
        .initialize(
          onSelected: (payload) {
            unawaited(
              activationService
                  .activatePayload(payload)
                  .catchError(_ignoreProviderAsyncError),
            );
          },
        )
        .then<void>((_) {
          initialized = true;
        });
    await initializing;
  }

  if (hooksEnabled && notificationsEnabled) {
    unawaited(ensureInitialized().catchError(_ignoreProviderAsyncError));
  }

  ref.listen<Map<String, AgentStatusEntry>>(agentStatusControllerProvider, (
    previous,
    next,
  ) {
    if (!hooksEnabled || !notificationsEnabled) {
      return;
    }
    final pending = tracker.pendingNotifications(
      previous: previous,
      next: next,
    );
    if (pending.isEmpty) {
      return;
    }
    unawaited(
      _showAgentStatusNotifications(
        ref: ref,
        presenter: presenter,
        ensureInitialized: ensureInitialized,
        entries: pending,
      ).catchError(_ignoreProviderAsyncError),
    );
  });
});

final terminalRuntimeProvider = Provider<TerminalRuntime>((ref) {
  final terminalHostClient = ref.watch(terminalHostClientProvider);
  final agentHookReceiver = ref.watch(agentHookReceiverProvider);
  final runtime = XtermTerminalRuntime(
    ptySessionFactory: TerminalHostPtySessionFactory(
      client: terminalHostClient,
    ),
    initialSettings: ref.read(settingsControllerProvider).terminal,
    externalUriLauncher: ref.watch(externalUriLauncherProvider),
    agentHookEnvironmentBuilder:
        ({required terminalSessionId, required workspaceId, required tabId}) {
          final enabled = ref
              .read(settingsControllerProvider)
              .general
              .agentStatusHooksEnabled;
          if (!enabled) {
            return null;
          }
          return agentHookReceiver.launchEnvironmentFor(
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

Future<void> _showAgentStatusNotifications({
  required Ref ref,
  required AgentStatusNotificationPresenter presenter,
  required Future<void> Function() ensureInitialized,
  required List<AgentStatusEntry> entries,
}) async {
  await ensureInitialized();
  final state = ref.read(workbenchControllerProvider);
  for (final entry in entries) {
    final workspace = _findWorkspaceById(state, entry.workspaceId);
    final tab = _findTabById(state, entry.workspaceId, entry.tabId);
    final notification = composeAgentStatusNotification(
      entry: entry,
      workspaceName: workspace?.name,
      tabTitle: tab?.title,
    );
    if (notification == null) {
      continue;
    }
    await presenter.show(notification);
  }
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

class _RiverpodAgentNotificationWorkbenchNavigator
    implements AgentNotificationWorkbenchNavigator {
  _RiverpodAgentNotificationWorkbenchNavigator(this._ref);

  final Ref _ref;

  @override
  WorkbenchState get state => _ref.read(workbenchControllerProvider);

  @override
  Future<void> selectWorkspace({
    required Project project,
    required Workspace workspace,
  }) {
    return _ref
        .read(workbenchControllerProvider.notifier)
        .selectWorkspace(project: project, workspace: workspace);
  }

  @override
  void setActiveTab({required String workspaceId, required String tabId}) {
    _ref
        .read(workbenchControllerProvider.notifier)
        .setActiveTab(workspaceId: workspaceId, tabId: tabId);
  }
}

class _RiverpodAgentNotificationTerminalFocusRequester
    implements AgentNotificationTerminalFocusRequester {
  _RiverpodAgentNotificationTerminalFocusRequester(this._ref);

  final Ref _ref;

  @override
  void requestTerminalFocus({
    required Workspace workspace,
    required WorkspaceTabRecord tab,
  }) {
    _ref
        .read(terminalRuntimeProvider)
        .sessionFor(workspace: workspace, tab: tab)
        .requestFocus();
  }
}
