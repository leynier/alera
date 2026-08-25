part of 'ai_assist_registry.dart';

AiAssistAgentSpec openCodeAiAssistSpec({
  required AiAssistAgent agent,
  required String binary,
}) {
  return AiAssistAgentSpec(
    agent: agent,
    binary: binary,
    promptDelivery: AiPromptDelivery.stdin,
    modelsCommand: const <String>['models'],
    parseModels: parseLineModels,
    models: const <AiAssistModel>[
      AiAssistModel(
        id: 'opencode/deepseek-v4-flash-free',
        label: 'OpenCode DeepSeek V4 Flash Free',
      ),
    ],
    defaultModelId: 'opencode/deepseek-v4-flash-free',
    buildArgs:
        ({
          required prompt,
          required model,
          thinkingLevel,
          required timeoutSeconds,
        }) => <String>[
          'run',
          '--model',
          model,
          '--agent',
          'build',
          '--format',
          'default',
          if (thinkingLevel != null) ...<String>['--variant', thinkingLevel],
        ],
  );
}
