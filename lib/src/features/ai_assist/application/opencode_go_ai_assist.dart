part of 'ai_assist_registry.dart';

const String openCodeGoDefaultModelId = 'glm-5.3-flash';

const List<AiAssistModel> openCodeGoStaticModels = <AiAssistModel>[
  AiAssistModel(id: 'glm-5.3-flash', label: 'GLM-5.3-Flash'),
  AiAssistModel(id: 'glm-5.3', label: 'GLM-5.3'),
  AiAssistModel(id: 'glm-5.2', label: 'GLM-5.2'),
  AiAssistModel(id: 'glm-5.1', label: 'GLM-5.1'),
  AiAssistModel(id: 'grok-4.6', label: 'Grok 4.6'),
  AiAssistModel(id: 'gpt-5.6-luna', label: 'GPT 5.6 Luna'),
  AiAssistModel(id: 'kimi-k3', label: 'Kimi K3'),
  AiAssistModel(id: 'kimi-k2.7-code', label: 'Kimi K2.7 Code'),
  AiAssistModel(id: 'kimi-k2.6', label: 'Kimi K2.6'),
  AiAssistModel(id: 'longcat-2.0', label: 'LongCat-2.0'),
  AiAssistModel(id: 'mimo-v2.5', label: 'MiMo-V2.5'),
  AiAssistModel(id: 'mimo-v2.5-pro', label: 'MiMo-V2.5-Pro'),
  AiAssistModel(id: 'minimax-m3', label: 'MiniMax M3'),
  AiAssistModel(id: 'minimax-m2.7', label: 'MiniMax M2.7'),
  AiAssistModel(id: 'minimax-m2.5', label: 'MiniMax M2.5'),
  AiAssistModel(
    id: 'muse-spark-1.3-contributor',
    label: 'Muse Spark 1.3 Contributor',
  ),
  AiAssistModel(
    id: 'muse-spark-1.2-contributor',
    label: 'Muse Spark 1.2 Contributor',
  ),
  AiAssistModel(id: 'qwen3.8-max', label: 'Qwen3.8 Max'),
  AiAssistModel(id: 'qwen3.8-flash', label: 'Qwen3.8 Flash'),
  AiAssistModel(id: 'qwen3.7-max', label: 'Qwen3.7 Max'),
  AiAssistModel(id: 'qwen3.7-plus', label: 'Qwen3.7 Plus'),
  AiAssistModel(id: 'qwen3.6-plus', label: 'Qwen3.6 Plus'),
  AiAssistModel(id: 'deepseek-v4.1-flash', label: 'DeepSeek V4.1 Flash'),
  AiAssistModel(id: 'deepseek-v4-pro', label: 'DeepSeek V4 Pro'),
  AiAssistModel(id: 'deepseek-v4-flash', label: 'DeepSeek V4 Flash'),
  AiAssistModel(
    id: 'deepseek-v4-flash-vision-exp',
    label: 'DeepSeek V4 Flash Vision Exp',
  ),
  AiAssistModel(id: 'hy4-preview', label: 'Hy4 preview'),
  AiAssistModel(id: 'hy3', label: 'Hy3'),
];

final AiAssistAgentSpec openCodeGoAiAssistSpec = AiAssistAgentSpec(
  agent: .opencodeGo,
  binary: '',
  promptDelivery: .stdin,
  modelsCommand: null,
  parseModels: parseLineModels,
  models: openCodeGoStaticModels,
  defaultModelId: openCodeGoDefaultModelId,
  supportsRemoteDiscovery: true,
  diffOnlyAccess: .toolFree,
  buildArgs: ({
    required prompt,
    required model,
    thinkingLevel,
    required timeoutSeconds,
  }) => const <String>[],
);
