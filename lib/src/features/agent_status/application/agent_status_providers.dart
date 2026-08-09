import 'dart:async';

import 'package:alera/src/features/agent_status/application/agent_hook_reconciliation_service.dart';
import 'package:alera/src/features/agent_status/application/agent_awake_service.dart';
import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/application/agent_status_notification_activation_service.dart';
import 'package:alera/src/features/agent_status/application/agent_status_notification_scheduler.dart';
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
import 'package:alera/src/features/agent_status/infra/codex_transcript_status_watcher.dart';
import 'package:alera/src/features/app_window/application/app_window_providers.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/shared/infra/process/process_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_status_notification_providers.dart';
part 'agent_status_providers.g.dart';

@Riverpod(keepAlive: true)
AgentHookReceiver agentHookReceiver(Ref ref) {
  final receiver = AgentHookReceiver(
    statusSink: ref.read(agentStatusControllerProvider.notifier),
    hookServer: ref.watch(agentHookServerProvider),
    // The transcript watchdog is the one poller that scales with how many
    // agents are running, so it is the one that parks while hidden.
    codexTranscriptStatusWatcher: CodexTranscriptStatusWatcher(
      ref.read(agentStatusControllerProvider.notifier),
      const Duration(seconds: 5),
      ref.watch(appForegroundProvider),
    ),
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
AgentHookReconciler agentHookReconciliationService(Ref ref) {
  return AgentHookReconciliationService(
    managedHooks: ref.watch(managedAgentHookInstallServiceProvider),
    codexRuntimeHome: ref.watch(codexRuntimeHomeServiceProvider),
    claudeRuntimeHome: ref.watch(claudeRuntimeHomeServiceProvider),
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
  final service = ref.watch(agentHookReconciliationServiceProvider);
  ref.listen<AgentStatusHookSettings>(
    settingsControllerProvider.select(
      (settings) => settings.agents.agentStatusHooks,
    ),
    (previous, next) {
      if (previous == null || previous == next) {
        return;
      }
      final operation = service.reconcile(next);
      unawaited(
        operation.then<void>((_) {}).catchError(_ignoreProviderAsyncError),
      );
    },
  );
}

/// Timings the notification coordinator buffers bursts with. A provider so

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
      hooks.opencode ||
      hooks.opencode2 ||
      hooks.pi ||
      hooks.amp) {
    try {
      await agentRuntimeOverlay.clearTerminalOverlays(terminalSessionId);
    } on Object catch (error, stackTrace) {
      _agentHookLog.warning(
        'failed to clear terminal overlays for $terminalSessionId; '
        'a stale overlay may shadow the new one',
        error,
        stackTrace,
      );
    }
  }
  if (hooks.codex) {
    await _addAgentHookEnvironment(environment, 'Codex', () async {
      return (await codexRuntimeHome.prepareForTerminalLaunch()).environment;
    });
  }
  if (hooks.claude) {
    await _addAgentHookEnvironment(environment, 'Claude', () async {
      return (await claudeRuntimeHome.prepareForTerminalLaunch()).environment;
    });
  }
  if (hooks.copilot) {
    await _addAgentHookEnvironment(environment, 'Copilot', () async {
      return (await agentRuntimeOverlay.prepareCopilotForTerminalLaunch(
        terminalSessionId: terminalSessionId,
      )).environment;
    });
  }
  // Cursor is deliberately absent: the runtime host builds its per-session
  // plugin and `cursor-agent` wrapper, because anything this side injects is
  // stripped again by the host's launch-environment sanitisation.
  if (hooks.opencode || hooks.opencode2) {
    await _addAgentHookEnvironment(environment, 'OpenCode', () async {
      return (await agentRuntimeOverlay.prepareOpenCodeForTerminalLaunch(
        terminalSessionId: terminalSessionId,
        includeV1Plugin: hooks.opencode,
        includeV2Plugin: hooks.opencode2,
      )).environment;
    });
  }
  if (hooks.pi) {
    await _addAgentHookEnvironment(environment, 'Pi', () async {
      return (await agentRuntimeOverlay.preparePiForTerminalLaunch(
        terminalSessionId: terminalSessionId,
      )).environment;
    });
  }
  if (hooks.amp) {
    await _addAgentHookEnvironment(environment, 'Amp', () async {
      return (await agentRuntimeOverlay.prepareAmpForTerminalLaunch(
        terminalSessionId: terminalSessionId,
      )).environment;
    });
  }
  return environment.isEmpty ? null : environment;
}

final Logger _agentHookLog = Logger('AgentHookLaunchEnvironment');

/// Merges one agent's launch environment, keeping a failure from blocking the
/// terminal.
///
/// A failure here is silent by design: the terminal must still open. That is
/// exactly why it has to be recorded. The user turned this hook on in Settings,
/// so without a log the agent simply never reports status and nothing explains
/// why the setting appears to do nothing.
Future<void> _addAgentHookEnvironment(
  Map<String, String> environment,
  String agent,
  Future<Map<String, String>> Function() prepare,
) async {
  try {
    environment.addAll(await prepare());
  } on Object catch (error, stackTrace) {
    _agentHookLog.warning(
      'failed to prepare the $agent hook environment; '
      'the terminal starts without agent status',
      error,
      stackTrace,
    );
  }
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
    AgentType.opencode2 => settings.opencode2,
    AgentType.pi => settings.pi,
    AgentType.amp => settings.amp,
    AgentType.grok => settings.grok,
  };
}

// coverage:ignore-start
/// Absorbs a failure from agent-status work started without awaiting it.
///
/// Discarding these meant the awake lock, the hook receiver and the status
/// reconciler could all fail without leaving anything behind, which reads to
/// the user as a status integration that silently does nothing.
void _ignoreProviderAsyncError(Object error, StackTrace stackTrace) {
  _agentHookLog.warning(
    'background agent status work failed',
    error,
    stackTrace,
  );
}

// coverage:ignore-end
