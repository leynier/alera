import 'package:alera/src/features/agents/application/agent_orchestrator.dart';
import 'package:alera/src/features/agents/infrastructure/codex_app_server_client.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/session/application/session_controller.dart';
import 'package:alera/src/features/session/application/session_service.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/settings/application/settings_service.dart';
import 'package:alera/src/features/steer/application/steer_controller.dart';
import 'package:alera/src/features/steer/domain/steer_state.dart';
import 'package:alera/src/shared/infra/process/io_process_runner.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/storage/preferences_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
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

final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService(ref.watch(preferencesStoreProvider));
});

final sessionServiceProvider = Provider<SessionService>((ref) {
  return SessionService(
    orchestrator: ref.watch(agentOrchestratorProvider),
    projectService: ref.watch(projectServiceProvider),
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
