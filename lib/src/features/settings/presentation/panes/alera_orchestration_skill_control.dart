import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/command_terminal/presentation/command_terminal_launcher.dart';
import 'package:alera/src/features/settings/infra/alera_cli_skill_service.dart';
import 'package:alera/src/features/settings/infra/alera_orchestration_setup_service.dart';
import 'package:alera/src/features/settings/presentation/panes/alera_skill_install_control.dart';
import 'package:alera/src/features/settings/presentation/panes/alera_skill_terminal_install_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const AleraOrchestrationSkillControl({super.key}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AleraSkillTerminalInstallControl(
      dialogTitle: 'Install Orchestration Skill',
      commandFor: (runner) =>
          aleraCliSkillInstallCommand(runner: runner, skill: .orchestration),
      runCommand: (context, request) =>
          showCommandTerminalDialog(context, ref, request),
      // Orchestration is the one skill whose setup does not end with the
      // installer: the agent status hooks are reconciled in Dart, so that half
      // runs once the terminal is done.
      followUp: () async {
        final service = AleraOrchestrationSetupService(
          skillService: ref.read(aleraCliSkillServiceProvider),
          hookReconciliationService: ref.read(
            agentHookReconciliationServiceProvider,
          ),
        );
        final result = await service.reconcileHooks(
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
