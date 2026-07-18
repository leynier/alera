import 'package:alera/src/features/settings/infra/alera_cli_skill_service.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AleraCliSkillService', () {
    test('copies auto command with npx to bunx fallback', () {
      expect(
        aleraCliSkillInstallCommand(runner: AleraCliSkillRunner.auto),
        'npx skills add https://github.com/leynier/alera --skill alera-cli --global || bunx skills add https://github.com/leynier/alera --skill alera-cli --global',
      );
    });

    test('builds the orchestration skill command', () {
      expect(
        aleraCliSkillInstallCommand(
          runner: AleraCliSkillRunner.bunx,
          skill: AleraAgentSkill.orchestration,
        ),
        'bunx skills add https://github.com/leynier/alera --skill alera-orchestration --global',
      );
    });

    test('passes hydrated environment to npx', () async {
      final runner = _FakeProcessRunner(<ProcessRunOutput>[
        const ProcessRunOutput(exitCode: 0, stdout: 'ok', stderr: ''),
      ]);
      final service = AleraCliSkillService(
        processRunner: runner,
        commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(
          <String, String>{'PATH': '/Users/test/.nvm/bin:/usr/bin'},
        ),
        operatingSystem: 'macos',
      );

      final result = await service.installOrUpdate(
        runner: AleraCliSkillRunner.npx,
      );

      expect(result.succeeded, isTrue);
      expect(result.summary, 'Install Complete (npx)');
      expect(runner.runs.single.executable, 'npx');
      expect(runner.runs.single.arguments, const <String>[
        'skills',
        'add',
        'https://github.com/leynier/alera',
        '--skill',
        'alera-cli',
        '--global',
      ]);
      expect(
        runner.runs.single.environment,
        containsPair('PATH', '/Users/test/.nvm/bin:/usr/bin'),
      );
    });

    test('auto falls back from missing npx to bunx', () async {
      final runner = _FakeProcessRunner(<ProcessRunOutput>[
        const ProcessRunOutput(
          exitCode: 127,
          stdout: '',
          stderr: '/bin/sh: npx: command not found',
        ),
        const ProcessRunOutput(exitCode: 0, stdout: 'ok', stderr: ''),
      ]);
      final service = AleraCliSkillService(
        processRunner: runner,
        commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(
          <String, String>{'PATH': '/Users/test/.bun/bin:/usr/bin'},
        ),
        operatingSystem: 'macos',
      );

      final result = await service.installOrUpdate();

      expect(result.succeeded, isTrue);
      expect(result.attempts.map((attempt) => attempt.runner), <Object>[
        AleraCliSkillRunner.npx,
        AleraCliSkillRunner.bunx,
      ]);
      expect(runner.runs.map((run) => run.executable), <String>['npx', 'bunx']);
    });

    test('passes the selected skill to the installer', () async {
      final runner = _FakeProcessRunner(<ProcessRunOutput>[
        const ProcessRunOutput(exitCode: 0, stdout: 'ok', stderr: ''),
      ]);
      final service = AleraCliSkillService(
        processRunner: runner,
        commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(
          <String, String>{'PATH': '/usr/bin'},
        ),
        operatingSystem: 'linux',
      );

      await service.installOrUpdate(
        runner: AleraCliSkillRunner.npx,
        skill: AleraAgentSkill.orchestration,
      );

      expect(runner.runs.single.arguments, contains('alera-orchestration'));
      expect(runner.runs.single.arguments, isNot(contains('alera-cli')));
    });

    test(
      'auto does not hide installer failures behind bunx fallback',
      () async {
        final runner = _FakeProcessRunner(<ProcessRunOutput>[
          const ProcessRunOutput(
            exitCode: 1,
            stdout: '',
            stderr: 'skills: network unavailable',
          ),
        ]);
        final service = AleraCliSkillService(
          processRunner: runner,
          commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(
            <String, String>{'PATH': '/usr/bin'},
          ),
          operatingSystem: 'macos',
        );

        final result = await service.installOrUpdate();

        expect(result.succeeded, isFalse);
        expect(result.summary, contains('skills: network unavailable'));
        expect(runner.runs, hasLength(1));
        expect(runner.runs.single.executable, 'npx');
      },
    );

    test('uses Windows runner names per package manager', () async {
      final runner = _FakeProcessRunner(<ProcessRunOutput>[
        const ProcessRunOutput(exitCode: 0, stdout: 'ok', stderr: ''),
        const ProcessRunOutput(exitCode: 0, stdout: 'ok', stderr: ''),
      ]);
      final service = AleraCliSkillService(
        processRunner: runner,
        commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(
          <String, String>{'Path': r'C:\Tools'},
        ),
        operatingSystem: 'windows',
      );

      await service.installOrUpdate(runner: AleraCliSkillRunner.npx);
      await service.installOrUpdate(runner: AleraCliSkillRunner.bunx);

      expect(runner.runs.map((run) => run.executable), <String>[
        'npx.cmd',
        'bunx',
      ]);
    });
  });
}

class _ProcessRun {
  const _ProcessRun({
    required this.executable,
    required this.arguments,
    required this.environment,
  });

  final String executable;
  final List<String> arguments;
  final Map<String, String>? environment;
}

class _FakeProcessRunner implements ProcessRunner {
  _FakeProcessRunner(this._outputs);

  final List<ProcessRunOutput> _outputs;
  final List<_ProcessRun> runs = <_ProcessRun>[];

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    runs.add(
      _ProcessRun(
        executable: executable,
        arguments: arguments,
        environment: environment,
      ),
    );
    return _outputs.removeAt(0);
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

class _FakeCommandEnvironmentResolver implements CommandEnvironmentResolver {
  const _FakeCommandEnvironmentResolver(this._environment);

  final Map<String, String> _environment;

  @override
  Future<Map<String, String>> environment() async => _environment;

  @override
  Future<Map<String, String>> environmentVariables(List<String> names) async =>
      const <String, String>{};
}
