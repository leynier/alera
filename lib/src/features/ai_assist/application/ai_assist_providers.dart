import 'package:alera/src/features/ai_assist/application/ai_assist_agent_runner.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_host_completer.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_service.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_model_discovery_service.dart';
import 'package:alera/src/features/ai_assist/application/host_routed_ai_assist_service.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/process/process_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera/src/shared/infra/runtime/runtime_state_migration.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ai_assist_providers.g.dart';

@Riverpod(keepAlive: true)
AiAssistAgentRunner aiAssistAgentRunner(Ref ref) {
  return CliAiAssistAgentRunner(
    processRunner: ref.read(processRunnerProvider),
    hostCompleter: RuntimeHostAiAssistCompleter(
      client: ref.read(runtimeHostClientProvider),
    ),
  );
}

@Riverpod(keepAlive: true)
AiAssistService aiAssistService(Ref ref) {
  return HostRoutedAiAssistService(
    local: CliAiAssistService(
      gitBackend: ref.read(gitBackendProvider),
      processRunner: ref.read(processRunnerProvider),
      runner: ref.read(aiAssistAgentRunnerProvider),
    ),
    client: ref.read(runtimeHostClientProvider),
    remoteWorkspaceIdFor: ref.read(remoteWorkspacePathResolverProvider),
    beforeAccess: ref.read(runtimeStateMigrationProvider).ensureMigrated,
  );
}

@Riverpod(keepAlive: true)
AiAssistModelDiscoveryService aiAssistModelDiscoveryService(Ref ref) {
  return CliAiAssistModelDiscoveryService(
    processRunner: ref.read(processRunnerProvider),
    hostCompleter: RuntimeHostAiAssistCompleter(
      client: ref.read(runtimeHostClientProvider),
    ),
  );
}
