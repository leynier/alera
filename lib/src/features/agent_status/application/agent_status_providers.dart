import 'dart:async';

import 'package:alera/src/features/agent_status/application/agent_awake_service.dart';
import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/application/agent_status_notification_activation_service.dart';
import 'package:alera/src/features/agent_status/application/agent_status_notifications.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_awake_assertions.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_receiver.dart';
import 'package:alera/src/features/agent_status/infra/agent_runtime_overlay_service.dart';
import 'package:alera/src/features/agent_status/infra/claude_runtime_home_service.dart';
import 'package:alera/src/features/agent_status/infra/codex_runtime_home_service.dart';
import 'package:alera/src/features/agent_status/infra/desktop_agent_status_notification_service.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:alera/src/features/agent_status/infra/window_manager_agent_window_activator.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/shared/infra/process/process_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_status_providers.g.dart';

@Riverpod(keepAlive: true)
AgentHookReceiver agentHookReceiver(Ref ref) {
  final receiver = AgentHookReceiver(
    statusSink: ref.read(agentStatusControllerProvider.notifier),
    hookServer: ref.watch(agentHookServerProvider),
    isAgentEnabled: (agentType) => isAgentStatusHookEnabled(
      ref.read(settingsControllerProvider).agents.agentStatusHooks,
      agentType,
    ),
  );
  ref.onDispose(() {
    unawaited(receiver.dispose());
  });
  return receiver;
}

@Riverpod(keepAlive: true)
AgentHookServer agentHookServer(Ref ref) {
  return RustAgentHookServer();
}

@Riverpod(keepAlive: true)
ManagedAgentHookInstallService managedAgentHookInstallService(Ref ref) {
  return ManagedAgentHookInstallService();
}

@Riverpod(keepAlive: true)
CodexRuntimeHomeService codexRuntimeHomeService(Ref ref) {
  return CodexRuntimeHomeService();
}

@Riverpod(keepAlive: true)
ClaudeRuntimeHomeService claudeRuntimeHomeService(Ref ref) {
  return ClaudeRuntimeHomeService();
}

@Riverpod(keepAlive: true)
AgentRuntimeOverlayService agentRuntimeOverlayService(Ref ref) {
  return AgentRuntimeOverlayService();
}

@Riverpod(keepAlive: true)
AgentStatusNotificationPresenter agentStatusNotificationPresenter(Ref ref) {
  return DesktopAgentStatusNotificationService();
}

@Riverpod(keepAlive: true)
AgentNotificationWindowActivator agentStatusNotificationWindowActivator(
  Ref ref,
) {
  return const WindowManagerAgentWindowActivator();
}

@Riverpod(keepAlive: true)
AgentNotificationWorkbenchNavigator agentStatusNotificationWorkbenchNavigator(
  Ref ref,
) {
  return _RiverpodAgentNotificationWorkbenchNavigator(ref);
}

@Riverpod(keepAlive: true)
AgentNotificationTerminalFocusRequester
agentStatusNotificationTerminalFocusRequester(Ref ref) {
  return _RiverpodAgentNotificationTerminalFocusRequester(ref);
}

@Riverpod(keepAlive: true)
AgentStatusNotificationActivationService
agentStatusNotificationActivationService(Ref ref) {
  return AgentStatusNotificationActivationService(
    windowActivator: ref.watch(agentStatusNotificationWindowActivatorProvider),
    navigator: ref.watch(agentStatusNotificationWorkbenchNavigatorProvider),
    terminalFocusRequester: ref.watch(
      agentStatusNotificationTerminalFocusRequesterProvider,
    ),
  );
}

@Riverpod(keepAlive: true)
AgentAwakeDisplayLock agentAwakeDisplayLock(Ref ref) {
  return const WakelockAgentAwakeDisplayLock();
}

@Riverpod(keepAlive: true)
List<AgentAwakeAssertion> agentAwakeAssertions(Ref ref) {
  final processRunner = ref.watch(processRunnerProvider);
  final now = ref.watch(agentStatusClockProvider);
  return <AgentAwakeAssertion>[
    MacosSystemSleepAssertion(processRunner: processRunner, now: now),
    LinuxLidSleepAssertion(processRunner: processRunner, now: now),
    WindowsSystemSleepAssertion(),
  ];
}

@Riverpod(keepAlive: true)
AgentAwakeService agentAwakeService(Ref ref) {
  final service = AgentAwakeService(
    displayLock: ref.watch(agentAwakeDisplayLockProvider),
    assertions: ref.watch(agentAwakeAssertionsProvider),
    now: ref.watch(agentStatusClockProvider),
  );
  unawaited(
    service
        .setHookSettings(
          ref.read(settingsControllerProvider).agents.agentStatusHooks,
        )
        .catchError(_ignoreProviderAsyncError),
  );
  unawaited(
    service
        .setStatuses(ref.read(agentStatusControllerProvider))
        .catchError(_ignoreProviderAsyncError),
  );
  unawaited(
    service
        .setEnabled(
          ref
              .read(settingsControllerProvider)
              .agents
              .keepComputerAwakeWhileAgentsWork,
        )
        .catchError(_ignoreProviderAsyncError),
  );
  ref.listen<AgentStatusHookSettings>(
    settingsControllerProvider.select(
      (settings) => settings.agents.agentStatusHooks,
    ),
    (_, next) {
      unawaited(
        service.setHookSettings(next).catchError(_ignoreProviderAsyncError),
      );
    },
  );
  ref.listen<bool>(
    settingsControllerProvider.select(
      (settings) => settings.agents.keepComputerAwakeWhileAgentsWork,
    ),
    (_, next) {
      unawaited(service.setEnabled(next).catchError(_ignoreProviderAsyncError));
    },
  );
  ref.listen<Map<String, AgentStatusEntry>>(agentStatusControllerProvider, (
    _,
    next,
  ) {
    unawaited(service.setStatuses(next).catchError(_ignoreProviderAsyncError));
  });
  ref.onDispose(() {
    unawaited(service.dispose().catchError(_ignoreProviderAsyncError));
  });
  return service;
}

@Riverpod(keepAlive: true)
void agentAwakeCoordinator(Ref ref) {
  ref.watch(agentAwakeServiceProvider);
}

@Riverpod(keepAlive: true)
void agentHookReceiverLifecycleCoordinator(Ref ref) {
  final hooks = ref.watch(
    settingsControllerProvider.select(
      (settings) => settings.agents.agentStatusHooks,
    ),
  );
  final receiver = ref.watch(agentHookReceiverProvider);
  if (hooks.anyEnabled) {
    unawaited(
      receiver.updateEnabledAgents().catchError(_ignoreProviderAsyncError),
    );
    unawaited(receiver.start().catchError(_ignoreProviderAsyncError));
  } else {
    unawaited(receiver.stop().catchError(_ignoreProviderAsyncError));
  }
}

@Riverpod(keepAlive: true)
void agentHookInstallerCoordinator(Ref ref) {
  final service = ref.watch(managedAgentHookInstallServiceProvider);
  final codexRuntimeHome = ref.watch(codexRuntimeHomeServiceProvider);
  final claudeRuntimeHome = ref.watch(claudeRuntimeHomeServiceProvider);
  ref.listen<AgentStatusHookSettings>(
    settingsControllerProvider.select(
      (settings) => settings.agents.agentStatusHooks,
    ),
    (previous, next) {
      if (previous == null || previous == next) {
        return;
      }
      final operation = _reconcileAgentHooks(
        service: service,
        codexRuntimeHome: codexRuntimeHome,
        claudeRuntimeHome: claudeRuntimeHome,
        settings: next,
      );
      unawaited(
        operation.then<void>((_) {}).catchError(_ignoreProviderAsyncError),
      );
    },
  );
}

@Riverpod(keepAlive: true)
void agentStatusNotificationCoordinator(Ref ref) {
  final hooksEnabled = ref.watch(
    settingsControllerProvider.select(
      (settings) => settings.agents.agentStatusHooks.anyEnabled,
    ),
  );
  final notificationsEnabled = ref.watch(
    settingsControllerProvider.select(
      (settings) => settings.agents.agentStatusNotificationsEnabled,
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
      next: Map<String, AgentStatusEntry>.fromEntries(
        next.entries.where(
          (entry) => isAgentStatusHookEnabled(
            ref.read(settingsControllerProvider).agents.agentStatusHooks,
            entry.value.agentType,
          ),
        ),
      ),
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
}

Future<Map<String, String>?> terminalLaunchEnvironmentFor({
  required AgentHookReceiver agentHookReceiver,
  required CodexRuntimeHomeService codexRuntimeHome,
  required ClaudeRuntimeHomeService claudeRuntimeHome,
  required AgentRuntimeOverlayService agentRuntimeOverlay,
  required AgentStatusHookSettings hooks,
  required String terminalSessionId,
  required String workspaceId,
  required String tabId,
}) async {
  final environment = <String, String>{};
  final hookEnvironment = await agentHookReceiver.launchEnvironmentFor(
    terminalSessionId: terminalSessionId,
    workspaceId: workspaceId,
    tabId: tabId,
  );
  if (hookEnvironment != null) {
    environment.addAll(hookEnvironment);
  }
  if (hooks.copilot ||
      hooks.cursor ||
      hooks.opencode ||
      hooks.pi ||
      hooks.amp) {
    try {
      await agentRuntimeOverlay.clearTerminalOverlays(terminalSessionId);
    } catch (_) {}
  }
  if (hooks.codex) {
    try {
      final preparation = await codexRuntimeHome.prepareForTerminalLaunch();
      environment.addAll(preparation.environment);
    } catch (_) {}
  }
  if (hooks.claude) {
    try {
      final preparation = await claudeRuntimeHome.prepareForTerminalLaunch();
      environment.addAll(preparation.environment);
    } catch (_) {}
  }
  if (hooks.copilot) {
    try {
      final preparation = await agentRuntimeOverlay
          .prepareCopilotForTerminalLaunch(
            terminalSessionId: terminalSessionId,
          );
      environment.addAll(preparation.environment);
    } catch (_) {}
  }
  if (hooks.cursor) {
    try {
      final preparation = await agentRuntimeOverlay
          .prepareCursorForTerminalLaunch(terminalSessionId: terminalSessionId);
      environment.addAll(preparation.environment);
    } catch (_) {}
  }
  if (hooks.opencode) {
    try {
      final preparation = await agentRuntimeOverlay
          .prepareOpenCodeForTerminalLaunch(
            terminalSessionId: terminalSessionId,
          );
      environment.addAll(preparation.environment);
    } catch (_) {}
  }
  if (hooks.pi) {
    try {
      final preparation = await agentRuntimeOverlay.preparePiForTerminalLaunch(
        terminalSessionId: terminalSessionId,
      );
      environment.addAll(preparation.environment);
    } catch (_) {}
  }
  if (hooks.amp) {
    try {
      final preparation = await agentRuntimeOverlay.prepareAmpForTerminalLaunch(
        terminalSessionId: terminalSessionId,
      );
      environment.addAll(preparation.environment);
    } catch (_) {}
  }
  return environment.isEmpty ? null : environment;
}

bool isAgentStatusHookEnabled(
  AgentStatusHookSettings settings,
  AgentType agentType,
) {
  return switch (agentType) {
    AgentType.codex => settings.codex,
    AgentType.claude => settings.claude,
    AgentType.copilot => settings.copilot,
    AgentType.cursor => settings.cursor,
    AgentType.agy => settings.agy,
    AgentType.opencode => settings.opencode,
    AgentType.pi => settings.pi,
    AgentType.amp => settings.amp,
  };
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
    final workspace = findWorkspaceById(state, entry.workspaceId);
    final project = workspace == null
        ? null
        : findProjectById(state, workspace.projectId);
    final tab = findTabById(state, entry.workspaceId, entry.tabId);
    final notification = composeAgentStatusNotification(
      entry: entry,
      projectName: project?.name,
      workspaceName: workspace?.name,
      tabTitle: tab?.title,
    );
    if (notification == null) {
      continue;
    }
    await presenter.show(notification);
  }
}

List<AgentType> _enabledAgentStatusHookTypes(AgentStatusHookSettings settings) {
  return <AgentType>[
    if (settings.codex) AgentType.codex,
    if (settings.claude) AgentType.claude,
    if (settings.copilot) AgentType.copilot,
    if (settings.cursor) AgentType.cursor,
    if (settings.agy) AgentType.agy,
    if (settings.opencode) AgentType.opencode,
    if (settings.pi) AgentType.pi,
    if (settings.amp) AgentType.amp,
  ];
}

List<AgentType> _globalManagedAgentTypes() {
  return <AgentType>[
    for (final agentType in AgentType.values)
      if (agentType != AgentType.codex &&
          agentType != AgentType.claude &&
          agentType != AgentType.copilot &&
          agentType != AgentType.cursor &&
          agentType != AgentType.opencode &&
          agentType != AgentType.pi &&
          agentType != AgentType.amp)
        agentType,
  ];
}

List<AgentType> _enabledGlobalManagedAgentStatusHookTypes(
  AgentStatusHookSettings settings,
) {
  return <AgentType>[
    for (final agentType in _enabledAgentStatusHookTypes(settings))
      if (agentType != AgentType.codex &&
          agentType != AgentType.claude &&
          agentType != AgentType.copilot &&
          agentType != AgentType.cursor &&
          agentType != AgentType.opencode &&
          agentType != AgentType.pi &&
          agentType != AgentType.amp)
        agentType,
  ];
}

Future<List<ManagedAgentHookInstallStatus>> _reconcileAgentHooks({
  required ManagedAgentHookInstallService service,
  required CodexRuntimeHomeService codexRuntimeHome,
  required ClaudeRuntimeHomeService claudeRuntimeHome,
  required AgentStatusHookSettings settings,
}) async {
  final results = await service.reconcile(
    enabledAgentTypes: _enabledGlobalManagedAgentStatusHookTypes(settings),
    agentTypes: _globalManagedAgentTypes(),
  );
  results.add(
    settings.codex
        ? await codexRuntimeHome.install()
        : await codexRuntimeHome.remove(),
  );
  results.add(
    settings.claude
        ? await claudeRuntimeHome.install()
        : await claudeRuntimeHome.remove(),
  );
  results.add(service.remove(AgentType.opencode));
  results.add(service.remove(AgentType.pi));
  return results;
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
