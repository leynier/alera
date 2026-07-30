import 'package:alera/src/features/agent_status/application/agent_hook_reconciliation_service.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/infra/alera_all_skills_setup_service.dart';
import 'package:alera/src/features/settings/infra/alera_cli_skill_service.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('installs every Alera skill and reapplies selected hooks', () async {
    final skillService = _RecordingSkillService();
    final hookReconciler = _RecordingHookReconciler();
    const hooks = AgentStatusHookSettings(codex: true);
    final result = await AleraAllSkillsSetupService(
      skillService: skillService,
      hookReconciliationService: hookReconciler,
    ).installOrUpdate(hooks: hooks, runner: AleraCliSkillRunner.bunx);

    expect(skillService.skills, AleraAgentSkill.values);
    expect(skillService.runners, everyElement(AleraCliSkillRunner.bunx));
    expect(hookReconciler.settings, hooks);
    expect(result.succeeded, isTrue);
    expect(result.needsAttention, isFalse);
    expect(result.summary, 'All 4 Alera Skills Installed / Updated');
    for (final skill in AleraAgentSkill.values) {
      expect(result.detail, contains(skill.name));
    }
  });

  test('continues installing remaining skills after one throws', () async {
    final skillService = _RecordingSkillService(
      throwingSkill: AleraAgentSkill.computerUse,
    );
    final result = await AleraAllSkillsSetupService(
      skillService: skillService,
      hookReconciliationService: _RecordingHookReconciler(),
    ).installOrUpdate(hooks: const AgentStatusHookSettings());

    expect(skillService.skills, AleraAgentSkill.values);
    expect(result.succeeded, isFalse);
    expect(result.needsAttention, isTrue);
    expect(result.succeededCount, 3);
    expect(result.summary, '3 Of 4 Alera Skills Installed / Updated');
    expect(result.detail, contains('computer-use'));
    expect(result.detail, contains('installer unavailable'));
    expect(result.detail, contains('alera-emulator'));
  });
}

class _RecordingSkillService extends AleraCliSkillService {
  _RecordingSkillService({this.throwingSkill})
    : super(
        processRunner: _NoopProcessRunner(),
        commandEnvironmentResolver: const _EmptyCommandEnvironmentResolver(),
      );

  final AleraAgentSkill? throwingSkill;
  final List<AleraAgentSkill> skills = <AleraAgentSkill>[];
  final List<AleraCliSkillRunner> runners = <AleraCliSkillRunner>[];

  @override
  Future<AleraCliSkillInstallResult> installOrUpdate({
    AleraCliSkillRunner runner = AleraCliSkillRunner.auto,
    AleraAgentSkill skill = AleraAgentSkill.cli,
  }) async {
    skills.add(skill);
    runners.add(runner);
    if (skill == throwingSkill) {
      throw StateError('installer unavailable');
    }
    return AleraCliSkillInstallResult(
      runner: runner,
      skill: skill,
      attempts: <AleraCliSkillInstallAttempt>[
        AleraCliSkillInstallAttempt(
          runner: runner == AleraCliSkillRunner.auto
              ? AleraCliSkillRunner.npx
              : runner,
          exitCode: 0,
          stdout: 'ok',
          stderr: '',
        ),
      ],
    );
  }
}

class _RecordingHookReconciler implements AgentHookReconciler {
  AgentStatusHookSettings? settings;

  @override
  Future<List<ManagedAgentHookInstallStatus>> reconcile(
    AgentStatusHookSettings settings,
  ) async {
    this.settings = settings;
    return <ManagedAgentHookInstallStatus>[
      const ManagedAgentHookInstallStatus(
        agentType: AgentType.codex,
        state: ManagedAgentHookInstallState.installed,
        configPath: '/tmp/codex',
        managedHooksPresent: true,
      ),
    ];
  }
}

class _NoopProcessRunner implements ProcessRunner {
  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) {
    throw UnimplementedError();
  }
}

class _EmptyCommandEnvironmentResolver implements CommandEnvironmentResolver {
  const _EmptyCommandEnvironmentResolver();

  @override
  Future<Map<String, String>> environment() async => const <String, String>{};

  @override
  Future<Map<String, String>> environmentVariables(List<String> names) async =>
      const <String, String>{};
}
