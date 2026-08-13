import 'package:alera/src/features/settings/infra/alera_cli_skill_service.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AleraCliSkillService', () {
    test('copies auto command with npx to bunx fallback', () {
      expect(
        aleraCliSkillInstallCommand(
          runner: AleraCliSkillRunner.auto,
          operatingSystem: 'linux',
        ),
        'npx skills add https://github.com/leynier/alera --skill alera-cli --agent codex --global --yes || bunx skills add https://github.com/leynier/alera --skill alera-cli --agent codex --global --yes',
      );
    });

    test('copies a single-line PowerShell auto command on windows', () {
      final command = aleraCliSkillInstallCommand(
        runner: AleraCliSkillRunner.auto,
        operatingSystem: 'windows',
      );
      expect(
        command,
        'if (Get-Command npx -ErrorAction SilentlyContinue) '
        '{ npx skills add https://github.com/leynier/alera --skill alera-cli --agent codex --global --yes } '
        'else { bunx skills add https://github.com/leynier/alera --skill alera-cli --agent codex --global --yes }',
      );
      expect(command, isNot(contains('||')));
      expect(command, isNot(contains('\n')));
    });

    test('builds one independent command for every bundled skill', () {
      final command = aleraAllSkillsInstallCommand(
        runner: AleraCliSkillRunner.bunx,
        operatingSystem: 'linux',
      );

      expect(command.split('; '), <String>[
        for (final skill in AleraAgentSkill.values)
          'bunx skills add https://github.com/leynier/alera --skill ${skill.name} --agent codex --global --yes',
      ]);
      expect(command, isNot(contains('\n')));
    });

    test('keeps the all-skills auto command single-line on windows', () {
      final command = aleraAllSkillsInstallCommand(
        runner: AleraCliSkillRunner.auto,
        operatingSystem: 'windows',
      );

      expect(command, isNot(contains('||')));
      expect(command, isNot(contains('\n')));
      expect(
        RegExp(r'if \(Get-Command npx').allMatches(command),
        hasLength(AleraAgentSkill.values.length),
      );
    });

    test('keeps explicit runners unwrapped on windows', () {
      expect(
        aleraCliSkillInstallCommand(
          runner: AleraCliSkillRunner.npx,
          operatingSystem: 'windows',
        ),
        'npx skills add https://github.com/leynier/alera --skill alera-cli --agent codex --global --yes',
      );
      expect(
        aleraCliSkillInstallCommand(
          runner: AleraCliSkillRunner.bunx,
          skill: AleraAgentSkill.orchestration,
          operatingSystem: 'windows',
        ),
        'bunx skills add https://github.com/leynier/alera --skill alera-orchestration --agent codex --global --yes',
      );
    });

    test('builds the orchestration skill command', () {
      expect(
        aleraCliSkillInstallCommand(
          runner: AleraCliSkillRunner.bunx,
          skill: AleraAgentSkill.orchestration,
        ),
        'bunx skills add https://github.com/leynier/alera --skill alera-orchestration --agent codex --global --yes',
      );
    });

    test('builds the computer use skill command', () {
      expect(
        aleraCliSkillInstallCommand(
          runner: AleraCliSkillRunner.bunx,
          skill: AleraAgentSkill.computerUse,
        ),
        'bunx skills add https://github.com/leynier/alera --skill computer-use --agent codex --global --yes',
      );
    });

    test('builds the emulator skill command', () {
      expect(
        aleraCliSkillInstallCommand(
          runner: AleraCliSkillRunner.npx,
          skill: AleraAgentSkill.emulator,
        ),
        'npx skills add https://github.com/leynier/alera --skill alera-emulator --agent codex --global --yes',
      );
    });

    test('builds the Agent Canvas skill command without confirmation', () {
      expect(
        aleraCliSkillInstallCommand(
          runner: AleraCliSkillRunner.npx,
          skill: AleraAgentSkill.agentCanvas,
        ),
        'npx skills add https://github.com/leynier/alera --skill agent-canvas --agent codex --global --yes',
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
        workingDirectory: '/tmp/alera-test',
      );

      final result = await service.installOrUpdate(
        runner: AleraCliSkillRunner.npx,
      );

      expect(result.succeeded, isTrue);
      expect(result.summary, 'Install complete (npx)');
      expect(runner.runs.single.executable, 'npx');
      expect(runner.runs.single.arguments, const <String>[
        'skills',
        'add',
        'https://github.com/leynier/alera',
        '--skill',
        'alera-cli',
        '--agent',
        'codex',
        '--global',
        '--yes',
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
        workingDirectory: '/tmp/alera-test',
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
        workingDirectory: '/tmp/alera-test',
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
          workingDirectory: '/tmp/alera-test',
        );

        final result = await service.installOrUpdate();

        expect(result.succeeded, isFalse);
        expect(result.summary, contains('skills: network unavailable'));
        expect(runner.runs, hasLength(1));
        expect(runner.runs.single.executable, 'npx');
      },
    );

    test('passes bare runner names so the shell resolves any shim', () async {
      final runner = _FakeProcessRunner(<ProcessRunOutput>[
        const ProcessRunOutput(exitCode: 0, stdout: 'ok', stderr: ''),
        const ProcessRunOutput(exitCode: 0, stdout: 'ok', stderr: ''),
      ]);
      final service = AleraCliSkillService(
        processRunner: runner,
        commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(
          <String, String>{'Path': r'C:\Tools'},
        ),
        workingDirectory: r'C:\Users\test',
      );

      await service.installOrUpdate(runner: AleraCliSkillRunner.npx);
      await service.installOrUpdate(runner: AleraCliSkillRunner.bunx);

      expect(runner.runs.map((run) => run.executable), <String>['npx', 'bunx']);
      expect(
        runner.runs.map((run) => run.workingDirectory),
        everyElement(r'C:\Users\test'),
      );
    });

    test('detail keeps both streams of a failing attempt', () async {
      final runner = _FakeProcessRunner(<ProcessRunOutput>[
        const ProcessRunOutput(
          exitCode: 1,
          stdout: 'npm warn exec downloading skills',
          stderr:
              'node:internal/modules/cjs/loader:1424\n'
              '        throw err;\n'
              "Error: Cannot find module 'C:\\shim\\npx-cli.js'",
        ),
      ]);
      final service = AleraCliSkillService(
        processRunner: runner,
        commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(
          <String, String>{'PATH': '/usr/bin'},
        ),
        workingDirectory: '/tmp/alera-test',
      );

      final result = await service.installOrUpdate(
        runner: AleraCliSkillRunner.npx,
      );

      expect(result.succeeded, isFalse);
      expect(
        result.summary,
        'Install failed (npx): node:internal/modules/cjs/loader:1424',
      );
      expect(result.summary, isNot(contains('\n')));
      expect(result.detail, contains('Cannot find module'));
      expect(result.detail, contains('npm warn exec downloading skills'));
      expect(result.detail, contains('exit code: 1'));
    });

    test('detail covers every auto attempt, not just the last', () async {
      final runner = _FakeProcessRunner(<ProcessRunOutput>[
        const ProcessRunOutput(
          exitCode: 9009,
          stdout: '',
          stderr: "'npx' is not recognized as an internal or external command",
        ),
        const ProcessRunOutput(
          exitCode: 1,
          stdout: 'bunx: registry unreachable',
          stderr: '',
        ),
      ]);
      final service = AleraCliSkillService(
        processRunner: runner,
        commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(
          <String, String>{'PATH': '/usr/bin'},
        ),
        workingDirectory: '/tmp/alera-test',
      );

      final result = await service.installOrUpdate();

      expect(result.succeeded, isFalse);
      expect(result.detail, contains('is not recognized'));
      expect(result.detail, contains('registry unreachable'));
      expect(result.detail, contains(r'$ npx skills add'));
      expect(result.detail, contains(r'$ bunx skills add'));
    });

    test('detail is empty on success', () async {
      final runner = _FakeProcessRunner(<ProcessRunOutput>[
        const ProcessRunOutput(exitCode: 0, stdout: 'added', stderr: ''),
      ]);
      final service = AleraCliSkillService(
        processRunner: runner,
        commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(
          <String, String>{'PATH': '/usr/bin'},
        ),
        workingDirectory: '/tmp/alera-test',
      );

      final result = await service.installOrUpdate(
        runner: AleraCliSkillRunner.npx,
      );

      expect(result.summary, 'Install complete (npx)');
      expect(result.detail, isEmpty);
    });
  });
}

class _ProcessRun {
  const _ProcessRun({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
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
        workingDirectory: workingDirectory,
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
    bool includeParentEnvironment = true,
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
