part of 'ai_text_generation_registry.dart';

final AiTextAgentSpec fxAiTextAgentSpec = AiTextAgentSpec(
  agent: AiTextGenerationAgent.fx,
  binary: 'fx',
  promptDelivery: AiPromptDelivery.stdin,
  modelsCommand: const <String>['models', '--json'],
  parseModels: parseFxModels,
  models: const <AiTextModel>[],
  defaultModelId: null,
  modelCanInherit: true,
  buildArgs:
      ({
        required model,
        thinkingLevel,
        required prompt,
        required timeoutSeconds,
      }) => const <String>['ask', '--no-save'],
);

List<AiTextModel> parseFxModels(String stdout) {
  try {
    final decoded = jsonDecode(stdout);
    if (decoded is! Map || decoded['models'] is! List) {
      return const <AiTextModel>[];
    }
    return _uniqueModels(
      (decoded['models'] as List)
          .whereType<Map>()
          .map((model) => model['id'])
          .whereType<String>()
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .map((id) => AiTextModel(id: id, label: labelFromModelId(id)))
          .toList(growable: false),
    );
  } catch (_) {
    return const <AiTextModel>[];
  }
}
