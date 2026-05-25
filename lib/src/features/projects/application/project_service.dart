import 'dart:io';

import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:path/path.dart' as p;

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

class LocalProjectInspectionResult {
  const LocalProjectInspectionResult._({required this.kind, this.message});

  final ProjectKind? kind;
  final String? message;

  bool get isValid => kind != null;

  factory LocalProjectInspectionResult.ok(ProjectKind kind) {
    return LocalProjectInspectionResult._(kind: kind);
  }

  factory LocalProjectInspectionResult.fail(String message) {
    return LocalProjectInspectionResult._(kind: null, message: message);
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

  Future<LocalProjectInspectionResult> inspectLocalProjectPath(
    String path,
  ) async {
    final dir = Directory(path);
    if (!dir.existsSync()) {
      return LocalProjectInspectionResult.fail(
        'path does not exist or cannot be accessed: $path',
      );
    }
    final gitValidation = await validateGitRepository(path);
    if (gitValidation.isValidGitRepository) {
      return LocalProjectInspectionResult.ok(ProjectKind.gitRepository);
    }
    return LocalProjectInspectionResult.ok(ProjectKind.folder);
  }

  Future<void> cloneGitRepository({
    required String url,
    required String destinationPath,
  }) async {
    final normalizedUrl = url.trim();
    final trimmedDestination = destinationPath.trim();
    if (normalizedUrl.isEmpty) {
      throw StateError('Git URL must not be empty');
    }
    if (trimmedDestination.isEmpty) {
      throw StateError('Destination path must not be empty');
    }
    final normalizedDestination = p.normalize(trimmedDestination);

    final destination = Directory(normalizedDestination);
    if (destination.existsSync()) {
      if (destination.listSync().isNotEmpty) {
        throw StateError(
          'Destination folder must be empty: $normalizedDestination',
        );
      }
    } else {
      final parent = Directory(p.dirname(normalizedDestination));
      if (!parent.existsSync()) {
        parent.createSync(recursive: true);
      }
    }

    final result = await _processRunner.run('git', <String>[
      'clone',
      '--progress',
      '--',
      normalizedUrl,
      normalizedDestination,
    ]);
    if (result.exitCode != 0) {
      final stderr = result.stderr.trim();
      throw StateError(
        stderr.isEmpty
            ? 'git clone failed (exit ${result.exitCode})'
            : 'git clone failed (exit ${result.exitCode}): $stderr',
      );
    }

    final validation = await validateGitRepository(normalizedDestination);
    if (!validation.isValidGitRepository) {
      throw StateError(
        validation.message ?? 'Cloned folder is not a git repository',
      );
    }
  }

  Future<List<String>> listGitBranches(String path) async {
    final result = await _processRunner.run('git', <String>[
      '-C',
      path,
      'for-each-ref',
      '--format=%(refname:short)',
      'refs/heads',
      'refs/remotes',
    ]);
    if (result.exitCode != 0) {
      return const <String>[];
    }
    final seen = <String>{};
    final branches = <String>[];
    for (final line in result.stdout.split('\n')) {
      final branch = line.trim();
      if (branch.isEmpty || branch.endsWith('/HEAD') || !seen.add(branch)) {
        continue;
      }
      branches.add(branch);
    }
    branches.sort();
    return branches;
  }
}
