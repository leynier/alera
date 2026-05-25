import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/infra/drift_project_repository.dart';
import 'package:alera/src/features/settings/application/settings_repository.dart';
import 'package:alera/src/features/settings/infra/drift_settings_repository.dart';
import 'package:alera/src/features/settings/infra/github_star_service.dart';
import 'package:alera/src/features/settings/infra/system_font_service.dart';
import 'package:alera/src/features/updater/application/update_service.dart';
import 'package:alera/src/features/updater/infra/desktop_update_service.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_view_prefs_repository.dart';
import 'package:alera/src/features/workbench/application/workspace_folder_opener.dart';
import 'package:alera/src/features/workbench/application/workspace_tab_service.dart';
import 'package:alera/src/features/workbench/infra/drift_workbench_repository.dart';
import 'package:alera/src/features/workbench/infra/drift_workbench_view_prefs_repository.dart';
import 'package:alera/src/shared/infra/process/io_process_runner.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/storage/drift_database.dart';
import 'package:alera/src/shared/infra/uri/external_uri_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

final processRunnerProvider = Provider<ProcessRunner>((ref) {
  return const IoProcessRunner();
});

final workspaceFolderOpenerProvider = Provider<WorkspaceFolderOpener>((ref) {
  return WorkspaceFolderOpener(processRunner: ref.watch(processRunnerProvider));
});

final projectServiceProvider = Provider<ProjectService>((ref) {
  return ProjectService(ref.watch(processRunnerProvider));
});

final aleraDatabaseProvider = FutureProvider<AleraDatabase>((ref) async {
  final db = await openAleraDb();
  ref.onDispose(() async {
    await db.close();
  });
  return db;
});

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  final dbAsync = ref.watch(aleraDatabaseProvider);
  final db = dbAsync.requireValue;
  return DriftProjectRepository(db);
});

final workbenchRepositoryProvider = Provider<WorkbenchRepository>((ref) {
  final dbAsync = ref.watch(aleraDatabaseProvider);
  final db = dbAsync.requireValue;
  return DriftWorkbenchRepository(db);
});

final workbenchViewPrefsRepositoryProvider =
    Provider<WorkbenchViewPrefsRepository>((ref) {
      final dbAsync = ref.watch(aleraDatabaseProvider);
      final db = dbAsync.requireValue;
      return DriftWorkbenchViewPrefsRepository(db);
    });

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final dbAsync = ref.watch(aleraDatabaseProvider);
  final db = dbAsync.requireValue;
  return DriftSettingsRepository(db);
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

final externalUriLauncherProvider = Provider<ExternalUriLauncher>((ref) {
  return UrlLauncherExternalUriLauncher();
});

final updateServiceProvider = Provider<AleraUpdateService>((ref) {
  final service = DesktopAleraUpdateService(
    client: ref.watch(updateHttpClientProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final projectsServiceProvider = Provider<ProjectsService>((ref) {
  return ProjectsService(
    projectService: ref.watch(projectServiceProvider),
    projectRepository: ref.watch(projectRepositoryProvider),
  );
});
