import 'dart:io';

import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';

const String aleraCliSkillRepositoryUrl = 'https://github.com/leynier/alera';
const String aleraCliSkillName = 'alera-cli';

enum AleraCliSkillRunner {
  auto('Auto'),
  npx('npx'),
  bunx('bunx');

  const AleraCliSkillRunner(this.label);

  final String label;
}

String aleraCliSkillInstallCommand({
  AleraCliSkillRunner runner = AleraCliSkillRunner.npx,
}) {
  final npxCommand = _installCommandFor(AleraCliSkillRunner.npx);
  if (runner == AleraCliSkillRunner.auto) {
    return '$npxCommand || ${_installCommandFor(AleraCliSkillRunner.bunx)}';
  }
  return _installCommandFor(runner);
}

String _installCommandFor(AleraCliSkillRunner runner) {
  return '${runner.label} skills add $aleraCliSkillRepositoryUrl --skill $aleraCliSkillName --global';
}

List<String> _aleraCliSkillInstallArguments = const <String>[
  'skills',
  'add',
  aleraCliSkillRepositoryUrl,
  '--skill',
  aleraCliSkillName,
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

  bool get runnerMissing {
    final detail = '${stderr.trim()}\n${stdout.trim()}'.toLowerCase();
    return exitCode == 127 ||
        exitCode == 9009 ||
        detail.contains('command not found') ||
        detail.contains('not recognized as an internal or external command') ||
        detail.contains('no such file or directory');
  }
}

class AleraCliSkillInstallResult {
  const AleraCliSkillInstallResult({
    required this.runner,
    required this.attempts,
  });

  final AleraCliSkillRunner runner;
  final List<AleraCliSkillInstallAttempt> attempts;

  AleraCliSkillInstallAttempt get lastAttempt => attempts.last;

  bool get succeeded => lastAttempt.succeeded;

  String get summary {
    if (succeeded) {
      return 'Install Complete (${lastAttempt.runner.label})';
    }
    final detail = lastAttempt.stderr.trim().isNotEmpty
        ? lastAttempt.stderr.trim()
        : lastAttempt.stdout.trim();
    if (detail.isEmpty) {
      return 'Install Failed';
    }
    return 'Install Failed: $detail';
  }
}

class AleraCliSkillService {
  AleraCliSkillService({
    required this.processRunner,
    CommandEnvironmentResolver? commandEnvironmentResolver,
    String? operatingSystem,
  }) : commandEnvironmentResolver =
           commandEnvironmentResolver ?? UserCommandEnvironmentResolver(),
       _operatingSystem = operatingSystem ?? Platform.operatingSystem;

  final ProcessRunner processRunner;
  final CommandEnvironmentResolver commandEnvironmentResolver;
  final String _operatingSystem;

  Future<AleraCliSkillInstallResult> installOrUpdate({
    AleraCliSkillRunner runner = AleraCliSkillRunner.auto,
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
      final attempt = await _run(candidate, environment);
      attempts.add(attempt);
      if (attempt.succeeded || !attempt.runnerMissing) {
        break;
      }
    }
    return AleraCliSkillInstallResult(
      runner: runner,
      attempts: List<AleraCliSkillInstallAttempt>.unmodifiable(attempts),
    );
  }

  Future<AleraCliSkillInstallAttempt> _run(
    AleraCliSkillRunner runner,
    Map<String, String> environment,
  ) async {
    final output = await processRunner.run(
      _executableFor(runner),
      _aleraCliSkillInstallArguments,
      environment: environment,
    );
    return AleraCliSkillInstallAttempt(
      runner: runner,
      exitCode: output.exitCode,
      stdout: output.stdout,
      stderr: output.stderr,
    );
  }

  String _executableFor(AleraCliSkillRunner runner) {
    if (_operatingSystem != 'windows') {
      return runner.label;
    }
    return switch (runner) {
      AleraCliSkillRunner.auto => AleraCliSkillRunner.npx.label,
      AleraCliSkillRunner.npx => 'npx.cmd',
      AleraCliSkillRunner.bunx => AleraCliSkillRunner.bunx.label,
    };
  }
}
