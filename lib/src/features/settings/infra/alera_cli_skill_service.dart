import 'dart:convert';
import 'dart:io';

import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('AleraCliSkillService');

const String aleraCliSkillRepositoryUrl = 'https://github.com/leynier/alera';
const String aleraCliSkillName = 'alera-cli';
const String aleraOrchestrationSkillName = 'alera-orchestration';
const String aleraComputerUseSkillName = 'computer-use';
const String aleraEmulatorSkillName = 'alera-emulator';

enum AleraAgentSkill {
  cli(aleraCliSkillName),
  orchestration(aleraOrchestrationSkillName),
  computerUse(aleraComputerUseSkillName),
  emulator(aleraEmulatorSkillName);

  const AleraAgentSkill(this.name);

  final String name;
}

enum AleraCliSkillRunner {
  auto('Auto'),
  npx('npx'),
  bunx('bunx');

  const AleraCliSkillRunner(this.label);

  final String label;
}

String aleraCliSkillInstallCommand({
  AleraCliSkillRunner runner = AleraCliSkillRunner.npx,
  AleraAgentSkill skill = AleraAgentSkill.cli,
  String? operatingSystem,
}) {
  if (runner != AleraCliSkillRunner.auto) {
    return _installCommandFor(runner, skill);
  }
  final os = operatingSystem ?? Platform.operatingSystem;
  if (os == 'windows') {
    return _windowsAutoInstallCommand(skill);
  }
  final npxCommand = _installCommandFor(AleraCliSkillRunner.npx, skill);
  return '$npxCommand || ${_installCommandFor(AleraCliSkillRunner.bunx, skill)}';
}

/// Windows PowerShell 5.1 has no `||` separator, and pasting a multi-line block
/// into its console runs each line as it arrives, so this stays one line.
/// `Get-Command` beats a `$LASTEXITCODE` chain because a missing `npx` raises
/// CommandNotFoundException without touching `$LASTEXITCODE`.
String _windowsAutoInstallCommand(AleraAgentSkill skill) {
  final npxCommand = _installCommandFor(AleraCliSkillRunner.npx, skill);
  final bunxCommand = _installCommandFor(AleraCliSkillRunner.bunx, skill);
  return 'if (Get-Command npx -ErrorAction SilentlyContinue) '
      '{ $npxCommand } else { $bunxCommand }';
}

String _installCommandFor(AleraCliSkillRunner runner, AleraAgentSkill skill) {
  return '${runner.label} skills add $aleraCliSkillRepositoryUrl --skill ${skill.name} --global';
}

List<String> _skillInstallArguments(AleraAgentSkill skill) => <String>[
  'skills',
  'add',
  aleraCliSkillRepositoryUrl,
  '--skill',
  skill.name,
  '--global',
];

class AleraCliSkillInstallAttempt {
  const AleraCliSkillInstallAttempt({
    required this.runner,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final AleraCliSkillRunner runner;
  final int exitCode;
  final String stdout;
  final String stderr;

  bool get succeeded => exitCode == 0;

  /// Both streams, because installers split their diagnostics across them and
  /// keeping only one has hidden the line that names the failure.
  String get output {
    return <String>[
      stderr.trim(),
      stdout.trim(),
    ].where((stream) => stream.isNotEmpty).join('\n');
  }

  bool get runnerMissing {
    final detail = output.toLowerCase();
    return exitCode == 127 ||
        exitCode == 9009 ||
        detail.contains('command not found') ||
        detail.contains('not recognized as an internal or external command') ||
        detail.contains('is not recognized') ||
        detail.contains('no such file or directory');
  }
}

class AleraCliSkillInstallResult {
  const AleraCliSkillInstallResult({
    required this.runner,
    required this.skill,
    required this.attempts,
  });

  final AleraCliSkillRunner runner;
  final AleraAgentSkill skill;
  final List<AleraCliSkillInstallAttempt> attempts;

  AleraCliSkillInstallAttempt get lastAttempt => attempts.last;

  bool get succeeded => lastAttempt.succeeded;

  /// One line, because the settings row renders it inline. The rest of the
  /// output belongs in [detail].
  String get summary {
    if (succeeded) {
      return 'Install Complete (${lastAttempt.runner.label})';
    }
    final headline = _firstLine(lastAttempt.output);
    if (headline.isEmpty) {
      return 'Install Failed (${lastAttempt.runner.label})';
    }
    return 'Install Failed (${lastAttempt.runner.label}): $headline';
  }

  /// Every attempt's full output, labelled per runner. An `auto` run that fell
  /// through to `bunx` still failed at `npx` first, and that attempt often
  /// carries the explanation.
  String get detail {
    if (succeeded) {
      return '';
    }
    return attempts
        .map((attempt) {
          final output = attempt.output;
          final body = output.isEmpty ? '(no output)' : output;
          return '\$ ${attempt.runner.label} '
              '${_skillInstallArguments(skill).join(' ')}\n'
              'exit code: ${attempt.exitCode}\n'
              '$body';
        })
        .join('\n\n');
  }
}

String _firstLine(String value) {
  for (final line in const LineSplitter().convert(value)) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return '';
}

class AleraCliSkillService {
  AleraCliSkillService({
    required this.processRunner,
    CommandEnvironmentResolver? commandEnvironmentResolver,
    this.workingDirectory,
  }) : commandEnvironmentResolver =
           commandEnvironmentResolver ?? UserCommandEnvironmentResolver();

  final ProcessRunner processRunner;
  final CommandEnvironmentResolver commandEnvironmentResolver;

  /// Overridable so tests do not depend on the machine's home directory.
  final String? workingDirectory;

  /// A GUI-launched app inherits whatever directory the launcher had, which on
  /// Windows is typically `C:\Windows\System32`. The installer unpacks and
  /// resolves relative to its working directory, so give it a writable one.
  String? get _resolvedWorkingDirectory {
    final configured = workingDirectory;
    if (configured != null) {
      return configured;
    }
    final environment = Platform.environment;
    for (final key in const <String>['HOME', 'USERPROFILE']) {
      final value = environment[key]?.trim();
      if (value != null && value.isNotEmpty && Directory(value).existsSync()) {
        return value;
      }
    }
    return null;
  }

  Future<AleraCliSkillInstallResult> installOrUpdate({
    AleraCliSkillRunner runner = AleraCliSkillRunner.auto,
    AleraAgentSkill skill = AleraAgentSkill.cli,
  }) async {
    final environment = await commandEnvironmentResolver.environment();
    final attempts = <AleraCliSkillInstallAttempt>[];
    final runners = runner == AleraCliSkillRunner.auto
        ? const <AleraCliSkillRunner>[
            AleraCliSkillRunner.npx,
            AleraCliSkillRunner.bunx,
          ]
        : <AleraCliSkillRunner>[runner];
    for (final candidate in runners) {
      final attempt = await _run(candidate, skill, environment);
      attempts.add(attempt);
      if (attempt.succeeded || !attempt.runnerMissing) {
        break;
      }
    }
    return AleraCliSkillInstallResult(
      runner: runner,
      skill: skill,
      attempts: List<AleraCliSkillInstallAttempt>.unmodifiable(attempts),
    );
  }

  Future<AleraCliSkillInstallAttempt> _run(
    AleraCliSkillRunner runner,
    AleraAgentSkill skill,
    Map<String, String> environment,
  ) async {
    final output = await processRunner.run(
      _executableFor(runner),
      _skillInstallArguments(skill),
      workingDirectory: _resolvedWorkingDirectory,
      environment: environment,
    );
    final attempt = AleraCliSkillInstallAttempt(
      runner: runner,
      exitCode: output.exitCode,
      stdout: output.stdout,
      stderr: output.stderr,
    );
    if (!attempt.succeeded) {
      _log.warning(
        '${skill.name} install via ${runner.label} exited '
        '${attempt.exitCode}: ${attempt.output}',
      );
    }
    return attempt;
  }

  /// The runner name is passed bare on every platform: `ProcessRunner` always
  /// goes through a shell, and `cmd.exe` resolves `PATHEXT` itself, so this
  /// finds a `.cmd`, `.bat`, or `.ps1` shim rather than only `.cmd`.
  String _executableFor(AleraCliSkillRunner runner) {
    return switch (runner) {
      AleraCliSkillRunner.auto => AleraCliSkillRunner.npx.label,
      AleraCliSkillRunner.npx || AleraCliSkillRunner.bunx => runner.label,
    };
  }
}
