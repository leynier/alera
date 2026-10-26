part of 'ai_assist_registry.dart';

AiAssistAgentSpec openCodeAiAssistSpec({
  required AiAssistAgent agent,
  required String binary,
}) {
  return AiAssistAgentSpec(
    agent: agent,
    binary: binary,
    promptDelivery: .stdin,
    modelsCommand: const <String>['models'],
    parseModels: parseLineModels,
    models: const <AiAssistModel>[
      AiAssistModel(
        id: 'opencode/deepseek-v4-flash-free',
        label: 'OpenCode DeepSeek V4 Flash Free',
      ),
    ],
    defaultModelId: 'opencode/deepseek-v4-flash-free',
    // The v1 shape; a run replaces it with the installed generation's
    // (see `_planCommand`), since OpenCode 2 rejects `--variant`.
    buildArgs:
        ({
          required prompt,
          required model,
          thinkingLevel,
          required timeoutSeconds,
        }) => openCodeRunArguments(
          model: model,
          thinkingLevel: thinkingLevel,
          generation: OpenCodeGeneration.v1,
        ),
  );
}
