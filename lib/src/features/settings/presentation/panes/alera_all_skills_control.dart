import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/command_terminal/presentation/command_terminal_launcher.dart';
import 'package:alera/src/features/settings/infra/alera_cli_skill_service.dart';
import 'package:alera/src/features/settings/infra/alera_orchestration_setup_service.dart';
import 'package:alera/src/features/settings/presentation/panes/alera_skill_install_control.dart';
import 'package:alera/src/features/settings/presentation/panes/alera_skill_terminal_install_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AleraAllSkillsControl extends ConsumerWidget {
  const AleraAllSkillsControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AleraSkillTerminalInstallControl(
      dialogTitle: 'Install All Alera Skills',
      commandFor: (runner) => aleraAllSkillsInstallCommand(runner: runner),
      runCommand: (context, request) =>
          showCommandTerminalDialog(context, ref, request),
      followUp: () async {
        final result =
            await AleraOrchestrationSetupService(
              skillService: ref.read(aleraCliSkillServiceProvider),
              hookReconciliationService: ref.read(
                agentHookReconciliationServiceProvider,
              ),
            ).reconcileHooks(
              ref.read(settingsControllerProvider).agents.agentStatusHooks,
            );
        return AleraSkillInstallStatus(
          result.summary,
          needsAttention: result.needsAttention,
        );
      },
    );
  }
}
