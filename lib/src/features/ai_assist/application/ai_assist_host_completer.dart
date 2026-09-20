import 'package:alera/src/features/ai_assist/application/ai_assist_agent_runner.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_errors.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_registry.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

const String openCodeGoHostTooOldMessage =
    'The running terminal host does not support OpenCode Go AI Assist.';

abstract interface class AiAssistHostCompleter {
  Future<AiAssistAgentRunResult> complete({
    required String prompt,
    required String model,
    required String sessionId,
    required String operationId,
    required int timeoutSeconds,
  });

  Future<void> cancel(String operationId);

  Future<List<AiAssistModel>> discoverOpenCodeGoModels();
}

class RuntimeHostAiAssistCompleter({required final RuntimeHostClient client})
    implements AiAssistHostCompleter {
  @override
  Future<AiAssistAgentRunResult> complete({
    required String prompt,
    required String model,
    required String sessionId,
    required String operationId,
    required int timeoutSeconds,
  }) async {
    await _requireCapability();
    try {
      final value = await client.runtimeRequest(
        'aiAssist.complete',
        <String, Object?>{
          'prompt': prompt,
          'model': model,
          'sessionId': sessionId,
          'operationId': operationId,
          'timeoutSeconds': timeoutSeconds,
        },
        Duration(seconds: timeoutSeconds + 10),
      );
      if (value is! Map) {
        throw const AiAssistException('OpenCode Go returned no text.');
      }
      final text = value['text']?.toString().trim() ?? '';
      if (text.isEmpty) {
        throw const AiAssistException('OpenCode Go returned no text.');
      }
      return AiAssistAgentRunResult(
        text: text,
        agentLabel: value['agentLabel']?.toString() ?? 'OpenCode Go',
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
  Future<List<AiAssistModel>> discoverOpenCodeGoModels() async {
    await _requireCapability();
    try {
      final value = await client.runtimeRequest(
        'aiAssist.opencodeGo.models',
        const <String, Object?>{},
        const Duration(seconds: aiAssistHostModelsTimeoutSeconds),
      );
      if (value is! Map) {
        throw const AiAssistException(
          'OpenCode Go returned no available models.',
        );
      }
      final rawModels = value['models'];
      if (rawModels is! List) {
        throw const AiAssistException(
          'OpenCode Go returned no available models.',
        );
      }
      final models = <AiAssistModel>[
        for (final item in rawModels)
          if (item is Map)
            AiAssistModel(
              id: item['id']?.toString().trim() ?? '',
              label:
                  item['label']?.toString().trim() ??
                  item['id']?.toString().trim() ??
                  '',
            ),
      ].where((model) => model.id.isNotEmpty).toList(growable: false);
      if (models.isEmpty) {
        throw const AiAssistException(
          'OpenCode Go returned no available models.',
        );
      }
      return models;
    } on AiAssistException {
      rethrow;
    } catch (error) {
      throw _mapHostError(error);
    }
  }

  Future<void> _requireCapability() async {
    if (client is! RuntimeHostCapabilityClient) {
      throw const AiAssistException(openCodeGoHostTooOldMessage);
    }
    final supported = await (client as RuntimeHostCapabilityClient)
        .supportsRuntimeCapability(
          aleraRuntimeHostAiAssistOpenCodeGoCapability,
        );
    if (!supported) {
      throw const AiAssistException(openCodeGoHostTooOldMessage);
    }
  }
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
