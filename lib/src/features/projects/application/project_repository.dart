import 'package:alera/src/features/projects/domain/project.dart';

abstract interface class ProjectRepository {
  Future<List<Project>> listAll();

  Stream<List<Project>> watchAll();

  Future<Project> add(Project project);

  Future<Project> update(Project project);

  Future<void> remove(String projectId);
}
