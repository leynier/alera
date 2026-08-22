import 'package:alera/src/features/agent_status/application/agent_hook_reconciliation_service.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/infra/alera_cli_skill_service.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('AleraOrchestrationSetupService');

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

  bool get needsAttention {
    return !succeeded ||
        hookError != null ||
        hookStatuses.any(
          (status) =>
              status.state == ManagedAgentHookInstallState.error ||
              status.state == ManagedAgentHookInstallState.partial,
        );
  }

  /// Forwarded so a failed orchestration setup exposes the same full installer
  /// output as the plain skill controls.
  String get detail => skillResult.detail;

  String get summary {
    if (!skillResult.succeeded) {
      return skillResult.summary;
    }
    if (hookError != null) {
      return 'Skill installed · hook setup failed: $hookError';
    }
    if (!hooksSelected) {
      return '${skillResult.summary} · no status hooks selected';
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
      return 'Skill installed · hooks need attention: $labels';
    }
    return '${skillResult.summary} · selected hooks ready';
  }
}

/// Outcome of the hook half of orchestration setup on its own, for when the
/// skill install already happened elsewhere.
class AleraOrchestrationHookSetupResult {
  const AleraOrchestrationHookSetupResult({
    required this.hooksSelected,
    this.hookStatuses = const <ManagedAgentHookInstallStatus>[],
    this.hookError,
  });

  final bool hooksSelected;
  final List<ManagedAgentHookInstallStatus> hookStatuses;
  final Object? hookError;

  List<ManagedAgentHookInstallStatus> get _unhealthy => hookStatuses
      .where(
        (status) =>
            status.state == ManagedAgentHookInstallState.error ||
            status.state == ManagedAgentHookInstallState.partial,
      )
      .toList(growable: false);

  bool get needsAttention => hookError != null || _unhealthy.isNotEmpty;

  String get summary {
    if (hookError != null) {
      return 'Hook setup failed: $hookError';
    }
    if (!hooksSelected) {
      return 'No status hooks selected';
    }
    final unhealthy = _unhealthy;
    if (unhealthy.isNotEmpty) {
      final labels = unhealthy
          .map((status) => _agentTypeLabel(status.agentType))
          .join(', ');
      return 'Hooks need attention: $labels';
    }
    return 'Selected hooks ready';
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
    } catch (error, stackTrace) {
      _log.warning(
        'orchestration hook setup failed after the skill install',
        error,
        stackTrace,
      );
      return AleraOrchestrationSetupResult(
        skillResult: skillResult,
        hooksSelected: hooks.anyEnabled,
        hookError: error,
      );
    }
  }

  /// Reconciles the status hooks without installing the skill first.
  ///
  /// The terminal dialog runs the skill install as a shell command the user can
  /// watch and answer; this is the half that stays in Dart and has to happen
  /// once that command is done.
  Future<AleraOrchestrationHookSetupResult> reconcileHooks(
    AgentStatusHookSettings hooks,
  ) async {
    try {
      final statuses = await hookReconciliationService.reconcile(hooks);
      final enabled = enabledAgentStatusHookTypes(hooks).toSet();
      return AleraOrchestrationHookSetupResult(
        hooksSelected: hooks.anyEnabled,
        hookStatuses: statuses
            .where((status) => enabled.contains(status.agentType))
            .toList(growable: false),
      );
    } catch (error, stackTrace) {
      _log.warning('orchestration hook setup failed', error, stackTrace);
      return AleraOrchestrationHookSetupResult(
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
    AgentType.opencode2 => 'OpenCode 2',
    AgentType.pi => 'Pi',
    AgentType.amp => 'Amp',
    AgentType.grok => 'Grok Build',
    AgentType.fx => 'fx',
  };
}
