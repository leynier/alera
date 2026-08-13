import 'ai_dictation_request.dart';
import 'ai_dictation_result.dart';

abstract interface class AiDictationProvider {
  String get id;

  Future<AiDictationResult> transcribe(AiDictationRequest request);

  Future<void> cancel(String requestId);
}
