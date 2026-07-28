import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/settings/infra/alera_cli_skill_service.dart';
import 'package:alera/src/features/settings/presentation/panes/alera_skill_install_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AleraEmulatorSkillControl extends ConsumerWidget {
  const AleraEmulatorSkillControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AleraSkillInstallControl(
      commandFor: (runner) => aleraCliSkillInstallCommand(
        runner: runner,
        skill: AleraAgentSkill.emulator,
      ),
      install: (runner) async {
        final result = await ref
            .read(aleraCliSkillServiceProvider)
            .installOrUpdate(runner: runner, skill: AleraAgentSkill.emulator);
        return AleraSkillInstallStatus(
          result.summary,
          detail: result.detail,
          needsAttention: !result.succeeded,
        );
      },
    );
  }
}
