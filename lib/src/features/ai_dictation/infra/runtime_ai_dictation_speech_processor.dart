import 'package:alera/src/features/ai_dictation/application/ai_dictation_target_registry.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_settings.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

abstract interface class AiDictationSpeechProcessor {
  Future<AiDictationSpeechProcessingResult> process({
    required String operationId,
    required String text,
    required AiDictationRewriteMode mode,
    required AiDictationTarget target,
  });

  Future<void> cancel(String operationId);
}

class const RuntimeAiDictationSpeechProcessor(final RuntimeHostClient _client)
    implements AiDictationSpeechProcessor {
  @override
  Future<AiDictationSpeechProcessingResult> process({
    required String operationId,
    required String text,
    required AiDictationRewriteMode mode,
    required AiDictationTarget target,
  }) async {
    final value = await _client.runtimeRequest(
      'aiText.speechMessage.generate',
      <String, Object?>{
        'operationId': operationId,
        'text': text,
        'mode': mode.name,
        'workspaceId': ?target.workspaceId,
        'tabId': ?target.tabId,
      },
    );
    if (value is! Map) {
      throw StateError('The speech processing response was invalid.');
    }
    final processed = value['text']?.toString().trim() ?? '';
    if (processed.isEmpty) {
      throw StateError('The speech processing agent returned no text.');
    }
    return AiDictationSpeechProcessingResult(
      text: processed,
      agentLabel: value['agentLabel']?.toString() ?? '',
      model: value['model']?.toString() ?? '',
    );
  }

  @override
  Future<void> cancel(String operationId) async {
    await _client.runtimeRequest('aiText.cancel', <String, Object?>{
      'operationId': operationId,
    });
  }
}

class const AiDictationSpeechProcessingResult({
  required final String text,
  required final String agentLabel,
  required final String model,
});
