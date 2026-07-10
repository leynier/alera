import 'package:alera/src/features/agent_status/application/agent_hook_reconciliation_service.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/managed_agent_hook_installer.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/infra/alera_cli_skill_service.dart';
import 'package:alera/src/features/settings/infra/alera_orchestration_setup_service.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'installs orchestration and reconciles only selected hook state',
    () async {
      final skillService = _FakeSkillService(succeeds: true);
      final reconciler = _FakeHookReconciler(<ManagedAgentHookInstallStatus>[
        _status(AgentType.codex, ManagedAgentHookInstallState.installed),
        _status(AgentType.agy, ManagedAgentHookInstallState.notInstalled),
      ]);
      final service = AleraOrchestrationSetupService(
        skillService: skillService,
        hookReconciliationService: reconciler,
      );
      const hooks = AgentStatusHookSettings(codex: true);

      final result = await service.installOrUpdate(
        hooks: hooks,
        runner: AleraCliSkillRunner.bunx,
      );

      expect(skillService.skill, AleraAgentSkill.orchestration);
      expect(skillService.runner, AleraCliSkillRunner.bunx);
      expect(reconciler.settings, hooks);
      expect(result.hookStatuses.map((status) => status.agentType), <AgentType>[
        AgentType.codex,
      ]);
      expect(result.summary, 'Install Complete (bunx) · Selected Hooks Ready');
    },
  );

  test('does not reconcile hooks when skill installation fails', () async {
    final reconciler = _FakeHookReconciler(
      const <ManagedAgentHookInstallStatus>[],
    );
    final service = AleraOrchestrationSetupService(
      skillService: _FakeSkillService(succeeds: false),
      hookReconciliationService: reconciler,
    );

    final result = await service.installOrUpdate(
      hooks: const AgentStatusHookSettings(codex: true),
    );

    expect(reconciler.settings, isNull);
    expect(result.succeeded, isFalse);
    expect(result.summary, contains('network unavailable'));
  });

  test(
    'reports partial success for selected hooks needing attention',
    () async {
      final service = AleraOrchestrationSetupService(
        skillService: _FakeSkillService(succeeds: true),
        hookReconciliationService:
            _FakeHookReconciler(<ManagedAgentHookInstallStatus>[
              _status(
                AgentType.codex,
                ManagedAgentHookInstallState.error,
                detail: 'conflict',
              ),
              _status(AgentType.claude, ManagedAgentHookInstallState.installed),
            ]),
      );

      final result = await service.installOrUpdate(
        hooks: const AgentStatusHookSettings(codex: true, claude: true),
      );

      expect(result.succeeded, isTrue);
      expect(result.summary, 'Skill Installed · Hooks Need Attention: Codex');
    },
  );

  test('reports when no status hooks are selected', () async {
    final service = AleraOrchestrationSetupService(
      skillService: _FakeSkillService(succeeds: true),
      hookReconciliationService: _FakeHookReconciler(
        const <ManagedAgentHookInstallStatus>[],
      ),
    );

    final result = await service.installOrUpdate(
      hooks: const AgentStatusHookSettings(),
    );

    expect(result.summary, 'Install Complete (npx) · No Status Hooks Selected');
  });
}

ManagedAgentHookInstallStatus _status(
  AgentType agentType,
  ManagedAgentHookInstallState state, {
  String? detail,
}) {
  return ManagedAgentHookInstallStatus(
    agentType: agentType,
    state: state,
    configPath: '/tmp/${agentType.key}',
    managedHooksPresent: state == ManagedAgentHookInstallState.installed,
    detail: detail,
  );
}

class _FakeSkillService extends AleraCliSkillService {
  _FakeSkillService({required this.succeeds})
    : super(
        processRunner: _NoopProcessRunner(),
        commandEnvironmentResolver: const _EmptyEnvironmentResolver(),
      );

  final bool succeeds;
  AleraAgentSkill? skill;
  AleraCliSkillRunner? runner;

  @override
  Future<AleraCliSkillInstallResult> installOrUpdate({
    AleraCliSkillRunner runner = AleraCliSkillRunner.auto,
    AleraAgentSkill skill = AleraAgentSkill.cli,
  }) async {
    this.skill = skill;
    this.runner = runner;
    return AleraCliSkillInstallResult(
      runner: runner,
      attempts: <AleraCliSkillInstallAttempt>[
        AleraCliSkillInstallAttempt(
          runner: runner == AleraCliSkillRunner.auto
              ? AleraCliSkillRunner.npx
              : runner,
          exitCode: succeeds ? 0 : 1,
          stdout: '',
          stderr: succeeds ? '' : 'network unavailable',
        ),
      ],
    );
  }
}

class _FakeHookReconciler implements AgentHookReconciler {
  _FakeHookReconciler(this.statuses);

  final List<ManagedAgentHookInstallStatus> statuses;
  AgentStatusHookSettings? settings;

  @override
  Future<List<ManagedAgentHookInstallStatus>> reconcile(
    AgentStatusHookSettings settings,
  ) async {
    this.settings = settings;
    return statuses;
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

class _EmptyEnvironmentResolver implements CommandEnvironmentResolver {
  const _EmptyEnvironmentResolver();

  @override
  Future<Map<String, String>> environment() async => const <String, String>{};
}
