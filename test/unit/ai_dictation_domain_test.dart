import 'package:alera/src/features/ai_dictation/domain/ai_dictation_error.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_request.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_result.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('constructs dictation settings and decodes persisted values', () {
    expect(AiDictationSettings.defaults.enabled, isFalse);
    final settings = AiDictationSettings.fromJson(<String, Object?>{
      'enabled': true,
      'providerPolicy': 'localOnly',
      'localModelId': 'whisper-cpp-base',
      'timeoutSeconds': 30,
    });

    expect(settings.enabled, isTrue);
    expect(settings.providerPolicy, AiDictationProviderPolicy.localOnly);
    expect(settings.timeoutSeconds, 30);
  });

  test('exposes exception details', () {
    const exception = AiDictationException(
      AiDictationErrorKind.cancelled,
      'Dictation cancelled.',
      cause: 'test',
    );

    expect(exception.kind, AiDictationErrorKind.cancelled);
    expect(exception.cause, 'test');
    expect(exception.toString(), 'Dictation cancelled.');
  });

  test('constructs transcription request and result values', () {
    final request = AiDictationRequest(
      requestId: String.fromCharCodes('request-1'.codeUnits),
      audioPath: '/tmp/audio.wav',
      modelPath: '/tmp/ggml-base.bin',
      language: 'en',
      initialPrompt: 'Alera terminal',
    );
    final result = AiDictationResult(
      text: 'hello',
      providerId: 'whisper-cpp-base',
      elapsed: Duration(milliseconds: int.parse('25')),
      duration: Duration(seconds: 1),
      detectedLanguage: 'en',
    );

    expect(request.requestId, 'request-1');
    expect(request.language, 'en');
    expect(result.text, 'hello');
    expect(result.duration, const Duration(seconds: 1));
  });
}
