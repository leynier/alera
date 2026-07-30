import 'package:alera/src/app/providers.dart';
import 'package:alera/src/features/settings/infra/alera_all_skills_setup_service.dart';
import 'package:alera/src/features/settings/presentation/panes/alera_skill_install_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AleraAllSkillsControl extends ConsumerWidget {
  const AleraAllSkillsControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AleraSkillInstallControl(
      installLabel: 'Install / Update All',
      installingLabel: 'Installing All',
      install: (runner) async {
        final result =
            await AleraAllSkillsSetupService(
              skillService: ref.read(aleraCliSkillServiceProvider),
              hookReconciliationService: ref.read(
                agentHookReconciliationServiceProvider,
              ),
            ).installOrUpdate(
              runner: runner,
              hooks: ref
                  .read(settingsControllerProvider)
                  .agents
                  .agentStatusHooks,
            );
        return AleraSkillInstallStatus(
          result.summary,
          detail: result.detail,
          needsAttention: result.needsAttention,
        );
      },
    );
  }
}
