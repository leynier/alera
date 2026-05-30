import 'dart:io';

import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
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
  ProjectService(this._gitBackend);

  final GitBackend _gitBackend;

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

    try {
      final isRepository = await _gitBackend.isGitRepository(path);
      if (isRepository) {
        return ProjectValidationResult.ok();
      }
      return ProjectValidationResult.fail(
        'path is not a git repository: $path',
      );
    } on AccessDeniedException {
      return ProjectValidationResult.fail(
        'access denied by macOS sandbox for: $path',
      );
    } on GitException catch (error) {
      return ProjectValidationResult.fail(error.context);
    }
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

    try {
      await _gitBackend.clone(
        url: normalizedUrl,
        destinationPath: normalizedDestination,
      );
    } on GitException catch (error) {
      throw StateError('git clone failed: ${error.context}');
    }

    final validation = await validateGitRepository(normalizedDestination);
    if (!validation.isValidGitRepository) {
      throw StateError(
        validation.message ?? 'Cloned folder is not a git repository',
      );
    }
  }

  Future<List<String>> listGitBranches(String path) async {
    // The backend already sorts, de-duplicates, and drops `*/HEAD` entries.
    try {
      return await _gitBackend.listBranches(path);
    } on GitException {
      return const <String>[];
    }
  }
}
