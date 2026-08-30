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
    final engine = request.remoteEngine;
    if (engine == null) {
      throw const AiDictationException(
        AiDictationErrorKind.invalidRequest,
        'A remote dictation engine is required.',
      );
    }
    try {
      final value = await _client.runtimeRequest(
        'aiDictation.transcribe',
        <String, Object?>{
          'requestId': request.requestId,
          'audioPath': request.audioPath,
          'engine': switch (engine) {
            AiDictationRemoteEngine.codexSubscription => 'codexSubscription',
            AiDictationRemoteEngine.openAiCompatible => 'openAiCompatible',
          },
          'baseUrl': request.providerBaseUrl,
          'modelId': request.providerModel,
          'language': request.language,
          'initialPrompt': request.initialPrompt,
          'timeoutSeconds': request.timeout?.inSeconds,
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
        providerId: value['providerId'] as String? ?? id,
        elapsed: Duration(milliseconds: (value['elapsedMillis'] as int?) ?? 0),
        duration: Duration(
          milliseconds: (value['durationMillis'] as int?) ?? 0,
        ),
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
