import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/infra/drift_project_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_folder_opener.dart';
import 'package:alera/src/shared/infra/process/process_providers.dart';
import 'package:alera/src/shared/infra/storage/storage_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'project_providers.g.dart';

@Riverpod(keepAlive: true)
WorkspaceFolderOpener workspaceFolderOpener(Ref ref) {
  return WorkspaceFolderOpener(processRunner: ref.watch(processRunnerProvider));
}

@Riverpod(keepAlive: true)
ProjectService projectService(Ref ref) {
  return ProjectService(ref.watch(processRunnerProvider));
}

@Riverpod(keepAlive: true)
ProjectRepository projectRepository(Ref ref) {
  final dbAsync = ref.watch(aleraDatabaseProvider);
  final db = dbAsync.requireValue;
  return DriftProjectRepository(db);
}

@Riverpod(keepAlive: true)
ProjectsService projectsService(Ref ref) {
  return ProjectsService(
    projectService: ref.watch(projectServiceProvider),
    projectRepository: ref.watch(projectRepositoryProvider),
  );
}
