import 'package:alera/src/features/ai_dictation/domain/ai_dictation_error.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_request.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_result.dart';
import 'package:alera/src/features/ai_dictation/domain/ai_dictation_settings.dart';
import 'package:alera/src/features/ai_dictation/application/ai_dictation_service.dart';
import 'package:alera/src/features/ai_dictation/infra/ai_dictation_model_store.dart';
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
    expect(settings.hostFallbackEnabled, isTrue);
    expect(settings.providerFallbackEnabled, isFalse);
    expect(
      settings.transcriptionEngine,
      AiDictationTranscriptionEngine.localWhisper,
    );
    expect(settings.rewriteMode, AiDictationRewriteMode.off);
    expect(
      AiDictationSettings.defaults.remoteBaseUrl,
      'https://api.openai.com/v1',
    );
    expect(AiDictationSettings.defaults.remoteModel, 'gpt-4o-mini-transcribe');
  });

  test('decodes remote transcription engine configuration', () {
    final settings = AiDictationSettings.fromJson(<String, Object?>{
      'enabled': true,
      'transcriptionEngine': 'codexSubscription',
      'codexRealtimeModel': 'realtime-model',
      'remoteConsentVersion': 1,
    });

    expect(
      settings.transcriptionEngine,
      AiDictationTranscriptionEngine.codexSubscription,
    );
    expect(settings.codexRealtimeModel, 'realtime-model');
    expect(settings.remoteConsentVersion, 1);
    expect(settings.toJson(), isNot(contains('providerApiKey')));
  });

  test('recording plan keeps the engine selected when recording started', () {
    final plan = AiDictationRecordingPlan(
      AiDictationSettings.defaults.copyWith(transcriptionEngine: .localWhisper),
    );

    plan.validateBeforeTranscription(
      AiDictationSettings.defaults.copyWith(
        transcriptionEngine: .openAiCompatible,
        remoteConsentVersion: 1,
      ),
    );

    expect(
      plan.settings.transcriptionEngine,
      AiDictationTranscriptionEngine.localWhisper,
    );
  });

  test('recording plan rejects remote upload after consent is revoked', () {
    final plan = AiDictationRecordingPlan(
      AiDictationSettings.defaults.copyWith(
        transcriptionEngine: .openAiCompatible,
        remoteConsentVersion: 1,
      ),
    );

    expect(
      () => plan.validateBeforeTranscription(.defaults),
      throwsA(
        isA<AiDictationException>().having(
          (error) => error.kind,
          'kind',
          AiDictationErrorKind.permissionDenied,
        ),
      ),
    );
  });

  test('exposes selectable verified local Whisper models', () {
    expect(
      AiDictationModelStore.models.map((model) => model.id),
      containsAll(<String>[
        'whisper-tiny',
        'whisper-base',
        'whisper-small',
        'whisper-large-v3-turbo-q5-0',
      ]),
    );
    expect(
      AiDictationModelStore.modelForId('whisper-cpp-base'),
      'whisper-base',
    );
  });

  test('exposes exception details', () {
    const exception = AiDictationException(
      .cancelled,
      'Dictation cancelled.',
      cause: 'test',
    );

    expect(exception.kind, AiDictationErrorKind.cancelled);
    expect(exception.cause, 'test');
    expect(exception.toString(), 'Dictation cancelled.');
  });

  test('constructs transcription request and result values', () {
    final request = AiDictationRequest(
      requestId: .fromCharCodes('request-1'.codeUnits),
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
