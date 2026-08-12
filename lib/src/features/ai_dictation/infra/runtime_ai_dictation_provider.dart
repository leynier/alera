import 'package:alera/src/features/ai_dictation/domain/ai_dictation_error.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_provider.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_request.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_result.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

class RuntimeAiDictationProvider implements AiDictationProvider {
  RuntimeAiDictationProvider(this._client);

  final RuntimeHostClient _client;

  @override
  String get id => 'runtime-whisper';

  @override
  Future<AiDictationResult> transcribe(AiDictationRequest request) async {
    try {
      final value = await _client.runtimeRequest(
        'aiDictation.transcribe',
        <String, Object?>{
          'requestId': request.requestId,
          'audioPath': request.audioPath,
          'modelId': request.providerModel,
          'modelPath': request.modelPath,
          'language': request.language,
          'initialPrompt': request.initialPrompt,
        },
        request.timeout,
      );
      if (value is! Map) {
        throw const FormatException('Invalid runtime dictation response.');
      }
      final text = value['text'];
      if (text is! String || text.trim().isEmpty) {
        throw const FormatException('Runtime returned no transcription.');
      }
      return AiDictationResult(
        text: text.trim(),
        providerId: id,
        elapsed: Duration(milliseconds: (value['elapsedMillis'] as int?) ?? 0),
        duration:
            Duration(milliseconds: (value['durationMillis'] as int?) ?? 0),
        detectedLanguage: value['detectedLanguage'] as String?,
      );
    } on AiDictationException {
      rethrow;
    } on Object catch (error) {
      throw AiDictationException(
        AiDictationErrorKind.transcription,
        'Runtime Whisper transcription failed.',
        cause: error,
      );
    }
  }

  @override
  Future<void> cancel(String requestId) async {
    await _client.runtimeRequest('aiDictation.cancel', <String, Object?>{
      'requestId': requestId,
    });
  }
}
