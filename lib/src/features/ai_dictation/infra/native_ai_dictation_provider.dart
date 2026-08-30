import 'package:alera/src/features/ai_dictation/domain/ai_dictation_error.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_provider.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_request.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_result.dart';
import 'package:alera/src/rust/api/ai_dictation.dart' as native;

class NativeAiDictationProvider implements AiDictationProvider {
  @override
  String get id => 'whisper-cpp-base';

  @override
  Future<AiDictationResult> transcribe(AiDictationRequest request) async {
    final modelPath = request.modelPath;
    if (modelPath == null || modelPath.trim().isEmpty) {
      throw const AiDictationException(
        .invalidRequest,
        'A local Whisper model is required for local transcription.',
      );
    }
    final stopwatch = Stopwatch()..start();
    try {
      final result = await native.transcribeWhisper(
        request: native.AiDictationRequest(
          requestId: request.requestId,
          audioPath: request.audioPath,
          modelPath: modelPath,
          language: request.language,
          initialPrompt: request.initialPrompt,
        ),
      );
      return AiDictationResult(
        text: result.text,
        providerId: id,
        elapsed: stopwatch.elapsed,
        duration: Duration(
          milliseconds: _durationMillis(result.durationMillis),
        ),
        detectedLanguage: result.detectedLanguage,
      );
    } on native.AiDictationError catch (error) {
      throw AiDictationException(
        _mapErrorKind(error.kind),
        error.message,
        cause: error,
      );
    } finally {
      stopwatch.stop();
    }
  }

  int _durationMillis(Object value) =>
      value is BigInt ? value.toInt() : value as int;

  @override
  Future<void> cancel(String requestId) async {
    await native.cancelWhisper(requestId: requestId);
  }

  AiDictationErrorKind _mapErrorKind(native.AiDictationErrorKind kind) {
    return switch (kind) {
      native.AiDictationErrorKind.invalidRequest =>
        AiDictationErrorKind.invalidRequest,
      native.AiDictationErrorKind.audio => AiDictationErrorKind.audio,
      native.AiDictationErrorKind.model =>
        AiDictationErrorKind.modelUnavailable,
      native.AiDictationErrorKind.cancelled => AiDictationErrorKind.cancelled,
      native.AiDictationErrorKind.inference =>
        AiDictationErrorKind.transcription,
      native.AiDictationErrorKind.io => AiDictationErrorKind.transcription,
    };
  }
}
