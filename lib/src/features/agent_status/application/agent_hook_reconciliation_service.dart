import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/claude_runtime_home_service.dart';
import 'package:alera/src/features/agent_status/infra/codex_runtime_home_service.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';

abstract interface class AgentHookReconciler {
  Future<List<ManagedAgentHookInstallStatus>> reconcile(
    AgentStatusHookSettings settings,
  );
}

class AgentHookReconciliationService implements AgentHookReconciler {
  const AgentHookReconciliationService({
    required this.managedHooks,
    required this.codexRuntimeHome,
    required this.claudeRuntimeHome,
  });

  final ManagedAgentHookInstallService managedHooks;
  final CodexRuntimeHomeService codexRuntimeHome;
  final ClaudeRuntimeHomeService claudeRuntimeHome;

  @override
  Future<List<ManagedAgentHookInstallStatus>> reconcile(
    AgentStatusHookSettings settings,
  ) async {
    final results = await managedHooks.reconcile(
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
    results.add(managedHooks.remove(AgentType.opencode));
    results.add(managedHooks.remove(AgentType.opencode2));
    results.add(managedHooks.remove(AgentType.pi));
    return results;
  }
}

List<AgentType> enabledAgentStatusHookTypes(AgentStatusHookSettings settings) {
  return <AgentType>[
    if (settings.codex) AgentType.codex,
    if (settings.claude) AgentType.claude,
    if (settings.copilot) AgentType.copilot,
    if (settings.cursor) AgentType.cursor,
    if (settings.agy) AgentType.agy,
    if (settings.opencode) AgentType.opencode,
    if (settings.opencode2) AgentType.opencode2,
    if (settings.pi) AgentType.pi,
    if (settings.amp) AgentType.amp,
    if (settings.grok) AgentType.grok,
    if (settings.fx) AgentType.fx,
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
          agentType != AgentType.opencode2 &&
          agentType != AgentType.pi &&
          agentType != AgentType.amp &&
          agentType != AgentType.fx)
        agentType,
  ];
}

List<AgentType> _enabledGlobalManagedAgentStatusHookTypes(
  AgentStatusHookSettings settings,
) {
  final enabled = enabledAgentStatusHookTypes(settings).toSet();
  return _globalManagedAgentTypes()
      .where((agentType) => enabled.contains(agentType))
      .toList(growable: false);
}
