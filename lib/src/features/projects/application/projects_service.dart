import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class ProjectsService {
  ProjectsService({
    required this._projectService,
    required this._projectRepository,
    Uuid? uuid,
    DateTime Function()? now,
  }) : _uuid = uuid ?? const Uuid(),
       _now = now ?? _defaultNow;

  final ProjectService _projectService;
  final ProjectRepository _projectRepository;
  final Uuid _uuid;
  final DateTime Function() _now;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  ProjectRepository get projectRepository => _projectRepository;

  /// Adds an existing local folder as a project. Git repositories are detected
  /// automatically; non-Git folders are registered as folder-only projects.
  Future<Project> addLocalProject({required String path, String? name}) async {
    final trimmed = path.trim();
    final normalized = p.normalize(trimmed);
    if (trimmed.isEmpty) {
      throw StateError('Project path must not be empty');
    }
    final inspection = await _projectService.inspectLocalProjectPath(
      normalized,
    );
    if (!inspection.isValid) {
      throw StateError(
        inspection.message ?? 'Selected folder cannot be used as a project',
      );
    }

    final existing = await _projectRepository.listAll();
    for (final candidate in existing) {
      if (p.equals(candidate.repoPath, normalized)) {
        return candidate;
      }
    }

    final project = _newProject(
      path: normalized,
      kind: inspection.kind!,
      name: name,
    );
    await _projectRepository.add(project);
    return project;
  }

  /// Clones a Git repository into [destinationPath] and registers the cloned
  /// checkout as a Git-backed project.
  Future<Project> cloneProject({
    required String gitUrl,
    required String destinationPath,
    String? name,
  }) async {
    final trimmedDestination = destinationPath.trim();
    final normalizedDestination = p.normalize(trimmedDestination);
    if (trimmedDestination.isEmpty) {
      throw StateError('Destination path must not be empty');
    }
    final existing = await _projectRepository.listAll();
    for (final candidate in existing) {
      if (p.equals(candidate.repoPath, normalizedDestination)) {
        throw StateError(
          'Project already registered at: $normalizedDestination',
        );
      }
    }

    await _projectService.cloneGitRepository(
      url: gitUrl,
      destinationPath: normalizedDestination,
    );
    final project = _newProject(
      path: normalizedDestination,
      kind: ProjectKind.gitRepository,
      name: name,
    );
    await _projectRepository.add(project);
    return project;
  }

  /// Backwards-compatible wrapper for existing callers. New UI should call
  /// [addLocalProject] or [cloneProject] to make the project origin explicit.
  Future<Project> addProject({required String repoPath, String? name}) async {
    return addLocalProject(path: repoPath, name: name);
  }

  Project _newProject({
    required String path,
    required ProjectKind kind,
    String? name,
  }) {
    final resolvedName = (name ?? '').trim().isEmpty
        ? p.basename(path)
        : name!.trim();
    final now = _now();
    final project = Project(
      id: _uuid.v4(),
      name: resolvedName,
      repoPath: path,
      createdAt: now,
      updatedAt: now,
      kind: kind,
    );
    return project;
  }

  Future<void> renameProject({
    required String projectId,
    required String name,
  }) async {
    final projects = await _projectRepository.listAll();
    Project? project;
    for (final candidate in projects) {
      if (candidate.id == projectId) {
        project = candidate;
        break;
      }
    }
    if (project == null) {
      throw StateError('project not found: $projectId');
    }
    final next = project.copyWith(name: name.trim(), updatedAt: _now());
    await _projectRepository.update(next);
  }

  Future<void> removeProject(String projectId) async {
    await _projectRepository.remove(projectId);
  }
}
