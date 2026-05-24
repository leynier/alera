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

  /// Validates that [repoPath] is a git repository and persists it as a new
  /// [Project]. The optional [name] defaults to the directory basename.
  Future<Project> addProject({required String repoPath, String? name}) async {
    final normalized = p.normalize(repoPath.trim());
    if (normalized.isEmpty) {
      throw StateError('Project path must not be empty');
    }
    final validation = await _projectService.validateGitRepository(normalized);
    if (!validation.isValidGitRepository) {
      throw StateError(
        validation.message ?? 'Selected folder is not a git repository',
      );
    }

    final existing = await _projectRepository.listAll();
    for (final candidate in existing) {
      if (p.equals(candidate.repoPath, normalized)) {
        return candidate;
      }
    }

    final resolvedName = (name ?? '').trim().isEmpty
        ? p.basename(normalized)
        : name!.trim();
    final project = Project(
      id: _uuid.v4(),
      name: resolvedName,
      repoPath: normalized,
      createdAt: _now(),
      updatedAt: _now(),
    );
    await _projectRepository.add(project);
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
