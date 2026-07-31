import 'package:alera/src/features/command_terminal/presentation/command_terminal_launcher.dart';
import 'package:alera/src/features/settings/infra/alera_cli_skill_service.dart';
import 'package:alera/src/features/settings/presentation/panes/alera_skill_terminal_install_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AleraEmulatorSkillControl extends ConsumerWidget {
  const AleraEmulatorSkillControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AleraSkillTerminalInstallControl(
      dialogTitle: 'Install Emulator Skill',
      commandFor: (runner) => aleraCliSkillInstallCommand(
        runner: runner,
        skill: AleraAgentSkill.emulator,
      ),
      runCommand: (context, request) =>
          showCommandTerminalDialog(context, ref, request),
    );
  }
}
