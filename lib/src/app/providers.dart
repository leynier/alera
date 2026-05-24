import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/infra/sembast_project_repository.dart';
import 'package:alera/src/features/settings/application/github_star_controller.dart';
import 'package:alera/src/features/settings/application/settings_controller.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:alera/src/features/settings/infra/github_star_service.dart';
import 'package:alera/src/features/settings/infra/sembast_settings_repository.dart';
import 'package:alera/src/features/settings/infra/system_font_service.dart';
import 'package:alera/src/features/updater/application/update_controller.dart';
import 'package:alera/src/features/updater/application/update_service.dart';
import 'package:alera/src/features/updater/domain/alera_update.dart';
import 'package:alera/src/features/updater/infra/desktop_update_service.dart';
import 'package:alera/src/features/workbench/application/workspace_tab_service.dart';
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
import 'package:http/http.dart' as http;
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

final settingsRepositoryProvider = Provider<SembastSettingsRepository>((ref) {
  final dbAsync = ref.watch(aleraDatabaseProvider);
  final db = dbAsync.requireValue;
  return SembastSettingsRepository(db);
});

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, AleraSettings>((ref) {
      return SettingsController(ref.watch(settingsRepositoryProvider));
    });

final workspaceServiceProvider = Provider<WorkspaceService>((ref) {
  final override = ref.watch(
    settingsControllerProvider.select((s) => s.general.workspaceDirectory),
  );
  return WorkspaceService(
    repository: ref.watch(workbenchRepositoryProvider),
    projectService: ref.watch(projectServiceProvider),
    processRunner: ref.watch(processRunnerProvider),
    workspaceRoot: WorkspaceRoot(override: override),
  );
});

final workspaceTabServiceProvider = Provider<WorkspaceTabService>((ref) {
  return WorkspaceTabService(
    repository: ref.watch(workbenchRepositoryProvider),
  );
});

final gitHubStarServiceProvider = Provider<GitHubStarService>((ref) {
  return GitHubStarService(ref.watch(processRunnerProvider));
});

final systemFontServiceProvider = Provider<SystemFontService>((ref) {
  return IoSystemFontService(ref.watch(processRunnerProvider));
});

final updateHttpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final updateServiceProvider = Provider<AleraUpdateService>((ref) {
  final service = DesktopAleraUpdateService(
    client: ref.watch(updateHttpClientProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final updateControllerProvider =
    StateNotifierProvider<AleraUpdateController, AleraUpdateState>((ref) {
      return AleraUpdateController(ref.watch(updateServiceProvider));
    });

final gitHubStarControllerProvider =
    StateNotifierProvider<GitHubStarController, GitHubStarState>((ref) {
      return GitHubStarController(ref.watch(gitHubStarServiceProvider));
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
        workspaceTabService: ref.watch(workspaceTabServiceProvider),
        viewPrefsRepository: ref.watch(workbenchViewPrefsRepositoryProvider),
      );
    });

final terminalRuntimeProvider = Provider<TerminalRuntime>((ref) {
  final runtime = XtermTerminalRuntime(
    initialSettings: ref.read(settingsControllerProvider).terminal,
  );
  ref.listen<TerminalSettings>(
    settingsControllerProvider.select((settings) => settings.terminal),
    (_, next) => runtime.updateSettings(next),
  );
  ref.onDispose(runtime.dispose);
  return runtime;
});
