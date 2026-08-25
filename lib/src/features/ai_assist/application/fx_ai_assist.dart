part of 'ai_assist_registry.dart';

final AiAssistAgentSpec fxAiAssistAgentSpec = AiAssistAgentSpec(
  agent: AiAssistAgent.fx,
  binary: 'fx',
  promptDelivery: AiPromptDelivery.stdin,
  modelsCommand: const <String>['models', '--json'],
  parseModels: parseFxModels,
  models: const <AiAssistModel>[],
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

List<AiAssistModel> parseFxModels(String stdout) {
  try {
    final decoded = jsonDecode(stdout);
    if (decoded is! Map || decoded['models'] is! List) {
      return const <AiAssistModel>[];
    }
    return _uniqueModels(
      (decoded['models'] as List)
          .whereType<Map>()
          .map((model) => model['id'])
          .whereType<String>()
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .map((id) => AiAssistModel(id: id, label: labelFromModelId(id)))
          .toList(growable: false),
    );
  } catch (_) {
    return const <AiAssistModel>[];
  }
}
