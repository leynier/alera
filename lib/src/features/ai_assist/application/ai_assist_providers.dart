import 'package:alera/src/features/ai_assist/application/ai_assist_agent_runner.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_service.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_model_discovery_service.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/process/process_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ai_assist_providers.g.dart';

@Riverpod(keepAlive: true)
AiAssistAgentRunner aiAssistAgentRunner(Ref ref) {
  return CliAiAssistAgentRunner(processRunner: ref.read(processRunnerProvider));
}

@Riverpod(keepAlive: true)
AiAssistService aiAssistService(Ref ref) {
  return CliAiAssistService(
    gitBackend: ref.read(gitBackendProvider),
    processRunner: ref.read(processRunnerProvider),
    runner: ref.read(aiAssistAgentRunnerProvider),
  );
}

@Riverpod(keepAlive: true)
AiAssistModelDiscoveryService aiAssistModelDiscoveryService(Ref ref) {
  return CliAiAssistModelDiscoveryService(
    processRunner: ref.read(processRunnerProvider),
  );
}
