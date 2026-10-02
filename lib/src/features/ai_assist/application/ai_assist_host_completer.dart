import 'package:alera/src/features/ai_assist/application/ai_assist_agent_runner.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_errors.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_registry.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

const String openCodeGoHostTooOldMessage =
    'The running terminal host does not support OpenCode Go AI Assist.';
const String chatGptOptionsHostTooOldMessage =
    'The running terminal host does not support ChatGPT thinking or fast mode.';

final class AiAssistThinkingContext {
  const AiAssistThinkingContext({
    this.operation,
    required this.selectedThinkingByModel,
    required this.selectedThinkingByOperation,
  });

  final AiAssistOperation? operation;
  final Map<String, String> selectedThinkingByModel;
  final Map<String, String> selectedThinkingByOperation;
}

abstract interface class AiAssistHostCompleter {
  Future<AiAssistAgentRunResult> complete({
    required String prompt,
    required String model,
    required String sessionId,
    required String operationId,
    required int timeoutSeconds,
    String? thinkingLevel,
    String? serviceTier,
    AiAssistThinkingContext? thinkingContext,
  });

  Future<void> cancel(String operationId);

  Future<List<AiAssistModel>> discoverModels();
}

class RuntimeHostAiAssistCompleter({
  required final RuntimeHostClient client,
  final AiAssistAgent agent = AiAssistAgent.opencodeGo,
}) implements AiAssistHostCompleter {
  @override
  Future<AiAssistAgentRunResult> complete({
    required String prompt,
    required String model,
    required String sessionId,
    required String operationId,
    required int timeoutSeconds,
    String? thinkingLevel,
    String? serviceTier,
    AiAssistThinkingContext? thinkingContext,
  }) async {
    await _requireCapability();
    await _requireChatGptOptionsCapability(
      thinkingLevel: thinkingLevel,
      serviceTier: serviceTier,
      thinkingContext: thinkingContext,
    );
    try {
      final normalizedThinkingLevel = thinkingLevel?.trim();
      final normalizedServiceTier = serviceTier?.trim();
      final effectiveServiceTier =
          normalizedServiceTier == null || normalizedServiceTier.isEmpty
          ? aiAssistChatGptDefaultServiceTier
          : normalizedServiceTier;
      final value = await client.runtimeRequest('aiAssist.complete', <
        String,
        Object?
      >{
        'agent': agent.key,
        'prompt': prompt,
        'model': model,
        'sessionId': sessionId,
        'operationId': operationId,
        'timeoutSeconds': timeoutSeconds,
        if (agent == AiAssistAgent.chatgpt &&
            normalizedThinkingLevel != null &&
            normalizedThinkingLevel.isNotEmpty)
          'thinkingLevel': normalizedThinkingLevel,
        if (agent == AiAssistAgent.chatgpt) 'serviceTier': effectiveServiceTier,
        if (agent == AiAssistAgent.chatgpt && thinkingContext != null)
          'thinkingContext': <String, Object?>{
            if (thinkingContext.operation != null)
              'operation': thinkingContext.operation!.key,
            'selectedThinkingByModel': thinkingContext.selectedThinkingByModel,
            'selectedThinkingByOperation':
                thinkingContext.selectedThinkingByOperation,
          },
      }, Duration(seconds: timeoutSeconds + 10));
      if (value is! Map) {
        throw AiAssistException('${agent.label} returned no text.');
      }
      final text = value['text']?.toString().trim() ?? '';
      if (text.isEmpty) {
        throw AiAssistException('${agent.label} returned no text.');
      }
      return AiAssistAgentRunResult(
        text: text,
        agentLabel: value['agentLabel']?.toString() ?? agent.label,
      );
    } on AiAssistException {
      rethrow;
    } catch (error) {
      throw _mapHostError(error);
    }
  }

  @override
  Future<void> cancel(String operationId) async {
    try {
      await client.runtimeRequest('aiText.cancel', <String, Object?>{
        'operationId': operationId,
      });
    } catch (_) {}
  }

  @override
  Future<List<AiAssistModel>> discoverModels() async {
    await _requireCapability();
    try {
      final value = await client.runtimeRequest(
        agent == AiAssistAgent.chatgpt
            ? 'aiAssist.chatgpt.models'
            : 'aiAssist.opencodeGo.models',
        const <String, Object?>{},
        const Duration(seconds: aiAssistHostModelsTimeoutSeconds),
      );
      if (value is! Map) {
        throw AiAssistException('${agent.label} returned no available models.');
      }
      final rawModels = value['models'];
      if (rawModels is! List) {
        throw AiAssistException('${agent.label} returned no available models.');
      }
      final models = <AiAssistModel>[
        for (final item in rawModels)
          if (item is Map) _parseModel(item),
      ].where((model) => model.id.isNotEmpty).toList(growable: false);
      final seenModelIds = <String>{};
      final uniqueModels = models
          .where((model) => seenModelIds.add(model.id))
          .toList(growable: false);
      if (uniqueModels.isEmpty) {
        throw AiAssistException('${agent.label} returned no available models.');
      }
      return uniqueModels;
    } on AiAssistException {
      rethrow;
    } catch (error) {
      throw _mapHostError(error);
    }
  }

  Future<void> _requireCapability() async {
    final message = agent == AiAssistAgent.chatgpt
        ? 'The running terminal host does not support ChatGPT AI Assist.'
        : openCodeGoHostTooOldMessage;
    if (client is! RuntimeHostCapabilityClient) {
      throw AiAssistException(message);
    }
    final supported = await (client as RuntimeHostCapabilityClient)
        .supportsRuntimeCapability(
          agent == AiAssistAgent.chatgpt
              ? aleraRuntimeHostAiAssistChatGptCapability
              : aleraRuntimeHostAiAssistOpenCodeGoCapability,
        );
    if (!supported) {
      throw AiAssistException(message);
    }
  }

  Future<void> _requireChatGptOptionsCapability({
    required String? thinkingLevel,
    required String? serviceTier,
    required AiAssistThinkingContext? thinkingContext,
  }) async {
    if (agent != AiAssistAgent.chatgpt ||
        ((thinkingLevel?.trim().isNotEmpty ?? false) == false &&
            serviceTier?.trim() != aiAssistChatGptFastServiceTier &&
            thinkingContext == null)) {
      return;
    }
    if (client is! RuntimeHostCapabilityClient) {
      throw const AiAssistException(chatGptOptionsHostTooOldMessage);
    }
    final supported = await (client as RuntimeHostCapabilityClient)
        .supportsRuntimeCapability(
          aleraRuntimeHostAiAssistChatGptOptionsCapability,
        );
    if (!supported) {
      throw const AiAssistException(chatGptOptionsHostTooOldMessage);
    }
  }
}

AiAssistModel _parseModel(Map item) {
  final id = _trimmedString(item['id']) ?? '';
  final label = _trimmedString(item['label']) ?? id;
  final levels = <AiThinkingLevel>[];
  final seenLevels = <String>{};
  final rawLevels = item['thinkingLevels'];
  if (rawLevels is List) {
    for (final rawLevel in rawLevels) {
      if (rawLevel is! Map) {
        continue;
      }
      final levelId = _trimmedString(rawLevel['id']);
      if (levelId == null || levelId.isEmpty || !seenLevels.add(levelId)) {
        continue;
      }
      final levelLabel = _trimmedString(rawLevel['label']) ?? levelId;
      levels.add(AiThinkingLevel(id: levelId, label: levelLabel));
    }
  }
  final candidateDefaultThinkingLevel = _trimmedString(
    item['defaultThinkingLevel'],
  );
  final defaultThinkingLevel =
      candidateDefaultThinkingLevel == null ||
          levels.isEmpty ||
          levels.any((level) => level.id == candidateDefaultThinkingLevel)
      ? candidateDefaultThinkingLevel
      : null;
  return AiAssistModel(
    id: id,
    label: label,
    thinkingLevels: levels,
    defaultThinkingLevel: defaultThinkingLevel,
  );
}

String? _trimmedString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

const int aiAssistHostModelsTimeoutSeconds = 60;

AiAssistException _mapHostError(Object error) {
  final message = error.toString();
  if (message == 'Generation canceled.' ||
      message == 'Bad state: Generation canceled.') {
    return const AiAssistCanceledException();
  }
  final trimmed = message.startsWith('Bad state: ')
      ? message.substring('Bad state: '.length)
      : message;
  return AiAssistException(trimmed);
}
