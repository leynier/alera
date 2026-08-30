import 'package:alera/src/features/agent_status/application/agent_hook_reconciliation_service.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/infra/alera_cli_skill_service.dart';
import 'package:alera/src/features/settings/infra/alera_orchestration_setup_service.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('AleraAllSkillsSetupService');

class const AleraSkillSetupOutcome({
  required final AleraAgentSkill skill,
  required final bool succeeded,
  required final String summary,
  required final String detail,
  required final bool needsAttention,
});

class const AleraAllSkillsSetupResult(
  final List<AleraSkillSetupOutcome> outcomes,
) {
  int get succeededCount =>
      outcomes.where((outcome) => outcome.succeeded).length;

  bool get succeeded => succeededCount == outcomes.length;

  bool get needsAttention => outcomes.any((outcome) => outcome.needsAttention);

  String get summary {
    if (succeeded) {
      final attention = needsAttention ? ' · setup needs attention' : '';
      return 'All ${outcomes.length} Alera skills installed / updated$attention';
    }
    return '$succeededCount of ${outcomes.length} Alera skills installed / updated';
  }

  String get detail {
    return outcomes
        .map((outcome) {
          final detail = outcome.detail.trim();
          return <String>[
            outcome.skill.name,
            outcome.summary,
            if (detail.isNotEmpty) detail,
          ].join('\n');
        })
        .join('\n\n');
  }
}

class const AleraAllSkillsSetupService({
  required final AleraCliSkillService skillService,
  required final AgentHookReconciler hookReconciliationService,
}) {
  Future<AleraAllSkillsSetupResult> installOrUpdate({
    required AgentStatusHookSettings hooks,
    AleraCliSkillRunner runner = AleraCliSkillRunner.auto,
  }) async {
    final outcomes = <AleraSkillSetupOutcome>[];
    for (final skill in AleraAgentSkill.values) {
      try {
        outcomes.add(
          await _installSkill(skill: skill, hooks: hooks, runner: runner),
        );
      } catch (error, stackTrace) {
        _log.warning(
          '${skill.name} install failed before producing a result',
          error,
          stackTrace,
        );
        outcomes.add(
          AleraSkillSetupOutcome(
            skill: skill,
            succeeded: false,
            summary: 'Install failed: $error',
            detail: '$error',
            needsAttention: true,
          ),
        );
      }
    }
    return AleraAllSkillsSetupResult(
      List<AleraSkillSetupOutcome>.unmodifiable(outcomes),
    );
  }

  Future<AleraSkillSetupOutcome> _installSkill({
    required AleraAgentSkill skill,
    required AgentStatusHookSettings hooks,
    required AleraCliSkillRunner runner,
  }) async {
    if (skill == AleraAgentSkill.orchestration) {
      final result = await AleraOrchestrationSetupService(
        skillService: skillService,
        hookReconciliationService: hookReconciliationService,
      ).installOrUpdate(hooks: hooks, runner: runner);
      return AleraSkillSetupOutcome(
        skill: skill,
        succeeded: result.succeeded,
        summary: result.summary,
        detail: result.detail,
        needsAttention: result.needsAttention,
      );
    }
    final result = await skillService.installOrUpdate(
      runner: runner,
      skill: skill,
    );
    return AleraSkillSetupOutcome(
      skill: skill,
      succeeded: result.succeeded,
      summary: result.summary,
      detail: result.detail,
      needsAttention: !result.succeeded,
    );
  }
}
