import 'dart:io';

import 'package:alera/src/shared/infra/process/process_runner.dart';

const String aleraCliSkillInstallCommand =
    'npx skills add https://github.com/leynier/alera --skill alera-cli --global';

class AleraCliSkillInstallResult {
  const AleraCliSkillInstallResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get succeeded => exitCode == 0;

  String get summary {
    if (succeeded) {
      return 'Install Complete';
    }
    final detail = stderr.trim().isNotEmpty ? stderr.trim() : stdout.trim();
    if (detail.isEmpty) {
      return 'Install Failed';
    }
    return 'Install Failed: $detail';
  }
}

class AleraCliSkillService {
  AleraCliSkillService({required this.processRunner, String? operatingSystem})
    : _operatingSystem = operatingSystem ?? Platform.operatingSystem;

  final ProcessRunner processRunner;
  final String _operatingSystem;

  Future<AleraCliSkillInstallResult> installOrUpdate() async {
    final output = await processRunner
        .run(_operatingSystem == 'windows' ? 'npx.cmd' : 'npx', const <String>[
          'skills',
          'add',
          'https://github.com/leynier/alera',
          '--skill',
          'alera-cli',
          '--global',
        ]);
    return AleraCliSkillInstallResult(
      exitCode: output.exitCode,
      stdout: output.stdout,
      stderr: output.stderr,
    );
  }
}
