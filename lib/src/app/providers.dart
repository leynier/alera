import 'dart:async';

import 'package:alera/src/app/dependencies.dart';
import 'package:alera/src/features/agent_status/application/agent_awake_service.dart';
import 'package:alera/src/features/agent_status/application/agent_status_notification_activation_service.dart';
import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
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
import 'package:alera/src/features/updater/application/update_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_pty_session.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/features/workbench/infra/terminal_shell_startup_preparer.dart';
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

part 'agent_hook_providers.dart';
part 'terminal_runtime_providers.dart';
part 'provider_integration_helpers.dart';

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
