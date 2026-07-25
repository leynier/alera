import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/application/project_config_repository.dart';
import 'package:alera/src/features/projects/application/project_config_service.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/project_config.dart';
import 'package:alera/src/features/projects/infra/runtime_project_config_repository.dart';
import 'package:alera/src/features/projects/infra/runtime_project_config_file_store.dart';
import 'package:alera/src/features/projects/infra/runtime_project_repository.dart';
import 'package:alera/src/features/projects/infra/runtime_project_management_client.dart';
import 'package:alera/src/features/workbench/application/workspace_folder_opener.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/process/process_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_state_migration.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'project_providers.g.dart';

@Riverpod(keepAlive: true)
WorkspaceFolderOpener workspaceFolderOpener(Ref ref) {
  return WorkspaceFolderOpener(processRunner: ref.watch(processRunnerProvider));
}

@Riverpod(keepAlive: true)
ProjectService projectService(Ref ref) {
  return ProjectService(ref.watch(gitBackendProvider));
}

@Riverpod(keepAlive: true)
ProjectRepository projectRepository(Ref ref) {
  return RuntimeProjectRepository(
    ref.watch(runtimeHostClientProvider),
    beforeAccess: ref.watch(runtimeStateMigrationProvider).ensureMigrated,
    coalescer: ref.watch(runtimeChangeCoalescerProvider),
  );
}

@Riverpod(keepAlive: true)
Stream<List<Project>> projectList(Ref ref) {
  return ref.watch(projectRepositoryProvider).watchAll();
}

@Riverpod(keepAlive: true)
ProjectConfigRepository projectConfigRepository(Ref ref) {
  return RuntimeProjectConfigRepository(
    ref.watch(runtimeHostClientProvider),
    beforeAccess: ref.watch(runtimeStateMigrationProvider).ensureMigrated,
    coalescer: ref.watch(runtimeChangeCoalescerProvider),
  );
}

@Riverpod(keepAlive: true)
ProjectConfigFileStore projectConfigFileStore(Ref ref) {
  return RuntimeProjectConfigFileStore(ref.watch(runtimeHostClientProvider));
}

@Riverpod(keepAlive: true)
ProjectConfigService projectConfigService(Ref ref) {
  return ProjectConfigService(
    repository: ref.watch(projectConfigRepositoryProvider),
    fileStore: ref.watch(projectConfigFileStoreProvider),
  );
}

@Riverpod(keepAlive: true)
Stream<Map<String, ProjectConfig>> projectConfigOverrides(Ref ref) {
  return ref.watch(projectConfigServiceProvider).watchUiOverrides();
}

@Riverpod(keepAlive: true)
ProjectsService projectsService(Ref ref) {
  return ProjectsService(
    projectService: ref.watch(projectServiceProvider),
    projectRepository: ref.watch(projectRepositoryProvider),
    removeProjectConfigOverride: ref
        .watch(projectConfigServiceProvider)
        .removeUiOverride,
    runtimeProjectManagement: RuntimeProjectManagementClient(
      ref.watch(runtimeHostClientProvider),
    ),
  );
}
