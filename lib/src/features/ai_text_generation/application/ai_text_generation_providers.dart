import 'package:alera/src/features/ai_text_generation/application/ai_text_agent_runner.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_service.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_model_discovery_service.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:alera/src/shared/infra/process/process_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'ai_text_generation_providers.g.dart';

@Riverpod(keepAlive: true)
AiTextAgentRunner aiTextAgentRunner(Ref ref) {
  return CliAiTextAgentRunner(processRunner: ref.read(processRunnerProvider));
}

@Riverpod(keepAlive: true)
AiTextGenerationService aiTextGenerationService(Ref ref) {
  return CliAiTextGenerationService(
    gitBackend: ref.read(gitBackendProvider),
    processRunner: ref.read(processRunnerProvider),
    runner: ref.read(aiTextAgentRunnerProvider),
  );
}

@Riverpod(keepAlive: true)
AiTextModelDiscoveryService aiTextModelDiscoveryService(Ref ref) {
  return CliAiTextModelDiscoveryService(
    processRunner: ref.read(processRunnerProvider),
  );
}
