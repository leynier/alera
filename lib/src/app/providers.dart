import 'package:alera/src/features/agents/application/agent_orchestrator.dart';
import 'package:alera/src/features/agents/infrastructure/codex_app_server_client.dart';
import 'package:alera/src/features/approvals/application/approval_service.dart';
import 'package:alera/src/features/commands/application/slash_command_registry.dart';
import 'package:alera/src/features/mcp/application/mcp_service.dart';
import 'package:alera/src/features/projects/application/project_service.dart';
import 'package:alera/src/features/session/application/session_controller.dart';
import 'package:alera/src/features/session/application/session_service.dart';
import 'package:alera/src/features/session/application/session_state.dart';
import 'package:alera/src/features/settings/application/settings_service.dart';
import 'package:alera/src/features/terminal/application/terminal_manager.dart';
import 'package:alera/src/features/worktree/application/branch_name_generator.dart';
import 'package:alera/src/features/worktree/application/worktree_service.dart';
import 'package:alera/src/shared/infra/db/app_database.dart';
import 'package:alera/src/shared/infra/db/app_database_factory.dart';
import 'package:alera/src/shared/infra/process/io_process_runner.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:alera/src/shared/infra/storage/preferences_store.dart';
import 'package:alera/src/shared/infra/storage/secure_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

final processRunnerProvider = Provider<ProcessRunner>((ref) {
  return const IoProcessRunner();
});

final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  return openAppDatabase();
});

final preferencesStoreProvider = Provider<StringStore>((ref) {
  try {
    return PreferencesStore(SharedPreferencesAsync());
  } catch (_) {
    return InMemoryPreferencesStore();
  }
});

final secureStoreProvider = Provider<SecureStore>((ref) {
  return const SecureStore(FlutterSecureStorage());
});

final codexAppServerClientProvider = Provider<CodexAppServerClient>((ref) {
  return CodexAppServerClient(processRunner: ref.watch(processRunnerProvider));
});

final agentOrchestratorProvider = Provider<AgentOrchestrator>((ref) {
  return AgentOrchestrator(ref.watch(codexAppServerClientProvider));
});

final branchNameGeneratorProvider = Provider<BranchNameGenerator>((ref) {
  return BranchNameGenerator();
});

final worktreeServiceProvider = Provider<WorktreeService>((ref) {
  return WorktreeService(
    processRunner: ref.watch(processRunnerProvider),
    branchNameGenerator: ref.watch(branchNameGeneratorProvider),
  );
});

final projectServiceProvider = Provider<ProjectService>((ref) {
  return ProjectService(ref.watch(processRunnerProvider));
});

final approvalServiceProvider = Provider<ApprovalService>((ref) {
  return ApprovalService(preferencesStore: ref.watch(preferencesStoreProvider));
});

final slashCommandRegistryProvider = Provider<SlashCommandRegistry>((ref) {
  return SlashCommandRegistry();
});

final settingsServiceProvider = Provider<SettingsService>((ref) {
  return SettingsService(ref.watch(preferencesStoreProvider));
});

final mcpServiceProvider = Provider<McpService>((ref) {
  return McpService(ref.watch(codexAppServerClientProvider));
});

final sessionServiceProvider = Provider<SessionService>((ref) {
  return SessionService(
    orchestrator: ref.watch(agentOrchestratorProvider),
    projectService: ref.watch(projectServiceProvider),
    worktreeService: ref.watch(worktreeServiceProvider),
    approvalService: ref.watch(approvalServiceProvider),
    commandRegistry: ref.watch(slashCommandRegistryProvider),
  );
});

final terminalManagerProvider = Provider<TerminalManager>((ref) {
  return TerminalManager(processRunner: ref.watch(processRunnerProvider));
});

final sessionControllerProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) {
  return SessionController(
    sessionService: ref.watch(sessionServiceProvider),
    terminalManager: ref.watch(terminalManagerProvider),
    mcpService: ref.watch(mcpServiceProvider),
    settingsService: ref.watch(settingsServiceProvider),
  );
});
