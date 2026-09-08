import 'package:alera/src/features/agent_profiles/application/agent_profile_providers.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_task_dispatch/application/agent_task_dispatch_service.dart';
import 'package:alera/src/features/agent_task_dispatch/domain/agent_task_dispatch.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_providers.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/infra/prompt_workspace_runtime_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_state_migration.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

AgentTaskDispatchCatalog agentTaskDispatchCatalogFrom({
  required WorkbenchState workbench,
  required Map<String, AgentStatusEntry> agentStatuses,
  required List<AgentProfile> profiles,
  required String workspaceId,
  String? defaultProfileId,
}) {
  return buildAgentTaskDispatchCatalog(
    tabs: workbench.tabsFor(workspaceId),
    agentStatuses: agentStatuses,
    profiles: profiles,
    defaultProfileId: defaultProfileId,
  );
}

AgentTaskDispatchCatalog readAgentTaskDispatchCatalog(
  WidgetRef ref,
  String workspaceId,
) {
  return agentTaskDispatchCatalogFrom(
    workbench: ref.read(workbenchControllerProvider),
    agentStatuses: ref.read(agentStatusControllerProvider),
    profiles:
        ref.read(agentProfilesProvider).asData?.value ?? const <AgentProfile>[],
    workspaceId: workspaceId,
    defaultProfileId: ref
        .read(settingsControllerProvider)
        .agents
        .defaultAgentProfileId,
  );
}

AgentTaskDispatchService wireAgentTaskDispatchService({
  required AgentTaskDispatchCatalog catalog,
  required WorkbenchState Function() currentWorkbench,
  required WorkbenchController controller,
  required TerminalRuntime terminalRuntime,
  required PromptWorkspaceRuntimeClient launchClient,
  String Function()? createMutationId,
}) {
  return AgentTaskDispatchService(
    catalog: catalog,
    findWorkspace: (id) => findWorkspaceById(currentWorkbench(), id),
    findTab: (id, tabId) {
      for (final tab in currentWorkbench().tabsFor(id)) {
        if (tab.id == tabId) {
          return tab;
        }
      }
      return null;
    },
    activateTab: (id, tabId) =>
        controller.selectWorkspaceTab(workspaceId: id, tabId: tabId),
    openPersistedTab: (id, tabId) =>
        controller.openPersistedWorkspaceTab(workspaceId: id, tabId: tabId),
    submitPrompt: ({required workspace, required tab, required prompt}) async {
      final handle = terminalRuntime.sessionFor(workspace: workspace, tab: tab);
      for (var attempt = 0; attempt < 5; attempt++) {
        if (await handle.submitText(prompt)) {
          return true;
        }
        await Future.pause(const Duration(milliseconds: 200));
        final stillThere = currentWorkbench()
            .tabsFor(workspace.id)
            .any((candidate) => candidate.id == tab.id);
        if (!stillThere) {
          return false;
        }
      }
      return false;
    },
    launchProfile:
        ({
          required workspaceId,
          required profileId,
          required prompt,
          required clientMutationId,
        }) {
          return launchClient.launchAgent(
            workspaceId: workspaceId,
            profileId: profileId,
            prompt: prompt,
            clientMutationId: clientMutationId,
            requireIdempotency: false,
          );
        },
    createMutationId: createMutationId ?? const Uuid().v4,
  );
}

AgentTaskDispatchService readAgentTaskDispatchService(
  WidgetRef ref, {
  AgentTaskDispatchCatalog? catalog,
  required String workspaceId,
}) {
  return _serviceFromReads(
    catalog: catalog ?? readAgentTaskDispatchCatalog(ref, workspaceId),
    readWorkbench: () => ref.read(workbenchControllerProvider),
    controller: ref.read(workbenchControllerProvider.notifier),
    terminalRuntime: ref.read(terminalRuntimeProvider),
    hostClient: ref.read(runtimeHostClientProvider),
    beforeAccess: ref.read(runtimeStateMigrationProvider).ensureMigrated,
  );
}

AgentTaskDispatchService readAgentTaskDispatchServiceFromRef(
  Ref ref, {
  AgentTaskDispatchCatalog? catalog,
  required String workspaceId,
}) {
  return _serviceFromReads(
    catalog:
        catalog ??
        agentTaskDispatchCatalogFrom(
          workbench: ref.read(workbenchControllerProvider),
          agentStatuses: ref.read(agentStatusControllerProvider),
          profiles:
              ref.read(agentProfilesProvider).asData?.value ??
              const <AgentProfile>[],
          workspaceId: workspaceId,
          defaultProfileId: ref
              .read(settingsControllerProvider)
              .agents
              .defaultAgentProfileId,
        ),
    readWorkbench: () => ref.read(workbenchControllerProvider),
    controller: ref.read(workbenchControllerProvider.notifier),
    terminalRuntime: ref.read(terminalRuntimeProvider),
    hostClient: ref.read(runtimeHostClientProvider),
    beforeAccess: ref.read(runtimeStateMigrationProvider).ensureMigrated,
  );
}

AgentTaskDispatchService _serviceFromReads({
  required AgentTaskDispatchCatalog catalog,
  required WorkbenchState Function() readWorkbench,
  required WorkbenchController controller,
  required TerminalRuntime terminalRuntime,
  required RuntimeHostClient hostClient,
  required Future<void> Function() beforeAccess,
}) {
  return wireAgentTaskDispatchService(
    catalog: catalog,
    currentWorkbench: readWorkbench,
    controller: controller,
    terminalRuntime: terminalRuntime,
    launchClient: PromptWorkspaceRuntimeClient(
      hostClient,
      beforeAccess: beforeAccess,
    ),
  );
}
