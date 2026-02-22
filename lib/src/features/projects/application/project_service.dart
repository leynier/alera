import 'dart:io';

import 'package:alera/src/shared/infra/process/process_runner.dart';

class ProjectValidationResult {
  const ProjectValidationResult._({
    required this.isValidGitRepository,
    this.message,
  });

  final bool isValidGitRepository;
  final String? message;

  factory ProjectValidationResult.ok() {
    return const ProjectValidationResult._(isValidGitRepository: true);
  }

  factory ProjectValidationResult.fail(String message) {
    return ProjectValidationResult._(
      isValidGitRepository: false,
      message: message,
    );
  }
}

class ProjectService {
  ProjectService(this._processRunner);

  final ProcessRunner _processRunner;

  Future<bool> isGitRepository(String path) async {
    final result = await validateGitRepository(path);
    return result.isValidGitRepository;
  }

  Future<ProjectValidationResult> validateGitRepository(String path) async {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      return ProjectValidationResult.fail(
        'path does not exist or cannot be accessed: $path',
      );
    }

    final gitEntryDirectory = Directory('$path/.git');
    final gitEntryFile = File('$path/.git');
    if (gitEntryDirectory.existsSync() || gitEntryFile.existsSync()) {
      return ProjectValidationResult.ok();
    }

    final result = await _processRunner.run('git', <String>[
      '-C',
      path,
      'rev-parse',
      '--is-inside-work-tree',
    ]);

    if (result.exitCode == 0 && result.stdout.trim() == 'true') {
      return ProjectValidationResult.ok();
    }

    final stderr = result.stderr.trim();
    if (stderr.isNotEmpty) {
      if (stderr.toLowerCase().contains('operation not permitted')) {
        return ProjectValidationResult.fail(
          'access denied by macOS sandbox for: $path',
        );
      }
      return ProjectValidationResult.fail(stderr);
    }

    return ProjectValidationResult.fail('path is not a git repository: $path');
  }
}
