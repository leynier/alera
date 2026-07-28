import 'package:alera/src/features/agent_status/application/agent_hook_reconciliation_service.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/infra/alera_cli_skill_service.dart';

class AleraOrchestrationSetupResult {
  const AleraOrchestrationSetupResult({
    required this.skillResult,
    required this.hooksSelected,
    this.hookStatuses = const <ManagedAgentHookInstallStatus>[],
    this.hookError,
  });

  final AleraCliSkillInstallResult skillResult;
  final bool hooksSelected;
  final List<ManagedAgentHookInstallStatus> hookStatuses;
  final Object? hookError;

  bool get succeeded => skillResult.succeeded;

  /// Forwarded so a failed orchestration setup exposes the same full installer
  /// output as the plain skill controls.
  String get detail => skillResult.detail;

  String get summary {
    if (!skillResult.succeeded) {
      return skillResult.summary;
    }
    if (hookError != null) {
      return 'Skill Installed · Hook Setup Failed: $hookError';
    }
    if (!hooksSelected) {
      return '${skillResult.summary} · No Status Hooks Selected';
    }
    final needsAttention = hookStatuses.where(
      (status) =>
          status.state == ManagedAgentHookInstallState.error ||
          status.state == ManagedAgentHookInstallState.partial,
    );
    if (needsAttention.isNotEmpty) {
      final labels = needsAttention
          .map((status) => _agentTypeLabel(status.agentType))
          .join(', ');
      return 'Skill Installed · Hooks Need Attention: $labels';
    }
    return '${skillResult.summary} · Selected Hooks Ready';
  }
}

class AleraOrchestrationSetupService {
  const AleraOrchestrationSetupService({
    required this.skillService,
    required this.hookReconciliationService,
  });

  final AleraCliSkillService skillService;
  final AgentHookReconciler hookReconciliationService;

  Future<AleraOrchestrationSetupResult> installOrUpdate({
    required AgentStatusHookSettings hooks,
    AleraCliSkillRunner runner = AleraCliSkillRunner.auto,
  }) async {
    final skillResult = await skillService.installOrUpdate(
      runner: runner,
      skill: AleraAgentSkill.orchestration,
    );
    if (!skillResult.succeeded) {
      return AleraOrchestrationSetupResult(
        skillResult: skillResult,
        hooksSelected: hooks.anyEnabled,
      );
    }
    try {
      final statuses = await hookReconciliationService.reconcile(hooks);
      final enabled = enabledAgentStatusHookTypes(hooks).toSet();
      return AleraOrchestrationSetupResult(
        skillResult: skillResult,
        hooksSelected: hooks.anyEnabled,
        hookStatuses: statuses
            .where((status) => enabled.contains(status.agentType))
            .toList(growable: false),
      );
    } catch (error) {
      return AleraOrchestrationSetupResult(
        skillResult: skillResult,
        hooksSelected: hooks.anyEnabled,
        hookError: error,
      );
    }
  }
}

String _agentTypeLabel(AgentType agentType) {
  return switch (agentType) {
    AgentType.codex => 'Codex',
    AgentType.claude => 'Claude Code',
    AgentType.copilot => 'GitHub Copilot',
    AgentType.cursor => 'Cursor',
    AgentType.agy => 'Antigravity',
    AgentType.opencode => 'OpenCode',
    AgentType.pi => 'Pi',
    AgentType.amp => 'Amp',
    AgentType.grok => 'Grok Build',
  };
}
