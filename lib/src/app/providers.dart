import 'package:alera/src/features/agents/application/agent_orchestrator.dart';
import 'package:alera/src/features/agents/infrastructure/codex_app_server_client.dart';
import 'package:alera/src/features/projects/application/chat_repository.dart';
import 'package:alera/src/features/projects/application/project_repository.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/projects/application/projects_controller.dart';
import 'package:alera/src/features/projects/application/projects_service.dart';
import 'package:alera/src/features/projects/application/projects_state.dart';
import 'package:alera/src/features/projects/application/worktree_service.dart';
import 'package:alera/src/features/projects/infra/sembast_chat_repository.dart';
import 'package:alera/src/features/projects/infra/sembast_project_repository.dart';
import 'package:alera/src/features/projects/infra/sembast_sidebar_prefs_repository.dart';
import 'package:alera/src/features/session/application/session_controller.dart';
import 'package:alera/src/features/session/application/session_service.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/settings/application/settings_service.dart';
import 'package:alera/src/features/steer/application/steer_controller.dart';
import 'package:alera/src/features/steer/domain/steer_state.dart';
import 'package:alera/src/features/workbench/application/terminal_tab_service.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/features/workbench/application/workbench_repository.dart';
import 'package:alera/src/features/workbench/application/workbench_state.dart';
import 'package:alera/src/features/workbench/application/workspace_service.dart';
import 'package:alera/src/features/workbench/infra/sembast_workbench_repository.dart';
import 'package:alera/src/features/workbench/infra/sembast_workbench_view_prefs_repository.dart';
import 'package:alera/src/features/workbench/presentation/terminal_runtime.dart';
import 'package:alera/src/shared/infra/process/io_process_runner.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/storage/preferences_store.dart';
import 'package:alera/src/shared/infra/storage/sembast_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:sembast/sembast.dart';
import 'package:shared_preferences/shared_preferences.dart';

final processRunnerProvider = Provider<ProcessRunner>((ref) {
  return const IoProcessRunner();
});

final preferencesStoreProvider = Provider<StringStore>((ref) {
  try {
    return PreferencesStore(SharedPreferencesAsync());
  } catch (_) {
    return InMemoryPreferencesStore();
  }
});

final codexAppServerClientProvider = Provider<CodexAppServerClient>((ref) {
  return CodexAppServerClient(processRunner: ref.watch(processRunnerProvider));
});

final agentOrchestratorProvider = Provider<AgentOrchestrator>((ref) {
  return AgentOrchestrator(ref.watch(codexAppServerClientProvider));
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

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final dbAsync = ref.watch(aleraDatabaseProvider);
  final db = dbAsync.requireValue;
  return SembastChatRepository(db);
});

final sidebarPrefsRepositoryProvider = Provider<SembastSidebarPrefsRepository>((
  ref,
) {
  final dbAsync = ref.watch(aleraDatabaseProvider);
  final db = dbAsync.requireValue;
  return SembastSidebarPrefsRepository(db);
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

final worktreeServiceProvider = Provider<WorktreeService>((ref) {
  return WorktreeService(
    projectRepository: ref.watch(projectRepositoryProvider),
    processRunner: ref.watch(processRunnerProvider),
  );
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
    chatRepository: ref.watch(chatRepositoryProvider),
    worktreeService: ref.watch(worktreeServiceProvider),
  );
});

final projectsControllerProvider =
    StateNotifierProvider<ProjectsController, ProjectsState>((ref) {
      return ProjectsController(
        projectsService: ref.watch(projectsServiceProvider),
        sidebarPrefsRepository: ref.watch(sidebarPrefsRepositoryProvider),
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

final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService(ref.watch(preferencesStoreProvider));
});

final sessionServiceProvider = Provider<SessionService>((ref) {
  // Read the chat repository through the asynchronous database provider so the
  // service is only constructed once Sembast is ready. Consumers await the
  // database via ref.watch(aleraDatabaseProvider) before using sessions.
  final chatRepoAsync = ref.watch(aleraDatabaseProvider);
  final chatRepository = chatRepoAsync.maybeWhen<ChatRepository?>(
    data: (_) => ref.watch(chatRepositoryProvider),
    orElse: () => null,
  );
  return SessionService(
    orchestrator: ref.watch(agentOrchestratorProvider),
    projectService: ref.watch(projectServiceProvider),
    chatRepository: chatRepository,
  );
});

final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) {
      final controller = SessionController(
        sessionService: ref.watch(sessionServiceProvider),
        projectService: ref.watch(projectServiceProvider),
        settingsService: ref.watch(settingsServiceProvider),
      );
      // Wire up steer context from SteerController.
      final steerController = ref.read(steerControllerProvider.notifier);
      controller.getSteerContext = steerController.getSteerContext;
      return controller;
    });

final steerControllerProvider =
    StateNotifierProvider<SteerController, SteerState>((ref) {
      return SteerController(
        preferencesStore: ref.watch(preferencesStoreProvider),
      );
    });
