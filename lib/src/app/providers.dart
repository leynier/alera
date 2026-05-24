import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/infra/sembast_project_repository.dart';
import 'package:alera/src/features/workbench/application/terminal_tab_service.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_folder_opener.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/infra/sembast_workbench_repository.dart';
import 'package:alera/src/features/workbench/infra/sembast_workbench_view_prefs_repository.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/shared/infra/process/io_process_runner.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/storage/sembast_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:sembast/sembast.dart';

final processRunnerProvider = Provider<ProcessRunner>((ref) {
  return const IoProcessRunner();
});

final workspaceFolderOpenerProvider = Provider<WorkspaceFolderOpener>((ref) {
  return WorkspaceFolderOpener(processRunner: ref.watch(processRunnerProvider));
});

final projectServiceProvider = Provider<ProjectService>((ref) {
  return ProjectService(ref.watch(processRunnerProvider));
});

final aleraDatabaseProvider = FutureProvider<Database>((ref) async {
  final db = await openAleraDb();
  ref.onDispose(() async {
    await db.close();
  });
  return db;
});

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  final dbAsync = ref.watch(aleraDatabaseProvider);
  final db = dbAsync.requireValue;
  return SembastProjectRepository(db);
});

final workbenchRepositoryProvider = Provider<WorkbenchRepository>((ref) {
  final dbAsync = ref.watch(aleraDatabaseProvider);
  final db = dbAsync.requireValue;
  return SembastWorkbenchRepository(db);
});

final workbenchViewPrefsRepositoryProvider =
    Provider<SembastWorkbenchViewPrefsRepository>((ref) {
      final dbAsync = ref.watch(aleraDatabaseProvider);
      final db = dbAsync.requireValue;
      return SembastWorkbenchViewPrefsRepository(db);
    });

final workspaceServiceProvider = Provider<WorkspaceService>((ref) {
  return WorkspaceService(
    repository: ref.watch(workbenchRepositoryProvider),
    projectService: ref.watch(projectServiceProvider),
    processRunner: ref.watch(processRunnerProvider),
  );
});

final terminalTabServiceProvider = Provider<TerminalTabService>((ref) {
  return TerminalTabService(repository: ref.watch(workbenchRepositoryProvider));
});

final projectsServiceProvider = Provider<ProjectsService>((ref) {
  return ProjectsService(
    projectService: ref.watch(projectServiceProvider),
    projectRepository: ref.watch(projectRepositoryProvider),
  );
});

final workbenchControllerProvider =
    StateNotifierProvider<WorkbenchController, WorkbenchState>((ref) {
      return WorkbenchController(
        projectsService: ref.watch(projectsServiceProvider),
        repository: ref.watch(workbenchRepositoryProvider),
        workspaceService: ref.watch(workspaceServiceProvider),
        terminalTabService: ref.watch(terminalTabServiceProvider),
        viewPrefsRepository: ref.watch(workbenchViewPrefsRepositoryProvider),
      );
    });

final terminalRuntimeProvider = Provider<TerminalRuntime>((ref) {
  final runtime = XtermTerminalRuntime();
  ref.onDispose(runtime.dispose);
  return runtime;
});
