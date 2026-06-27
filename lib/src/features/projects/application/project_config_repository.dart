import 'package:alera/src/features/projects/domain/project_config.dart';

abstract interface class ProjectConfigRepository {
  Future<ProjectConfig?> findByProjectId(String projectId);

  Future<Map<String, ProjectConfig>> loadAll();

  Stream<Map<String, ProjectConfig>> watchAll();

  Future<void> save({
    required String projectId,
    required ProjectConfig config,
    required DateTime updatedAt,
  });

  Future<void> remove(String projectId);
}
