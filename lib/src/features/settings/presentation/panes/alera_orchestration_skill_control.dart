import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:alera/src/features/settings/infra/alera_cli_skill_service.dart';
import 'package:alera/src/features/settings/infra/alera_orchestration_setup_service.dart';
import 'package:alera/src/features/settings/presentation/panes/alera_skill_install_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AleraOrchestrationSkillControl extends ConsumerWidget {
  const AleraOrchestrationSkillControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AleraSkillInstallControl(
      commandFor: (runner) => aleraCliSkillInstallCommand(
        runner: runner,
        skill: AleraAgentSkill.orchestration,
      ),
      install: (runner) async {
        final service = AleraOrchestrationSetupService(
          skillService: ref.read(aleraCliSkillServiceProvider),
          hookReconciliationService: ref.read(
            agentHookReconciliationServiceProvider,
          ),
        );
        final result = await service.installOrUpdate(
          runner: runner,
          hooks: ref.read(settingsControllerProvider).agents.agentStatusHooks,
        );
        return AleraSkillInstallStatus(
          result.summary,
          detail: result.detail,
          needsAttention:
              !result.succeeded ||
              result.hookError != null ||
              result.hookStatuses.any(
                (status) =>
                    status.state == ManagedAgentHookInstallState.error ||
                    status.state == ManagedAgentHookInstallState.partial,
              ),
        );
      },
    );
  }
}
