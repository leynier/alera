import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'defaults to opt-in on-device dictation without transcript rewriting',
    () {
      const settings = MobileAiDictationSettings();

      expect(settings.enabled, isFalse);
      expect(settings.location, MobileAiDictationLocation.thisDevice);
      expect(settings.engine, MobileAiDictationEngine.systemOnDevice);
      expect(settings.rewriteMode, MobileAiDictationRewriteMode.off);
      expect(settings.localModelId, 'whisper-base');
      expect(settings.remoteAudioConsentVersion, isNull);
      expect(settings.systemRecognitionConsentVersion, isNull);
      expect(settings.providerBaseUrl, 'https://api.openai.com/v1');
      expect(settings.providerModel, 'gpt-4o-mini-transcribe');
    },
  );

  test('decodes persisted recognition and processing choices', () {
    final settings = MobileAiDictationSettings.fromJson(<String, Object?>{
      'enabled': true,
      'location': 'thisDevice',
      'engine': 'systemRecognition',
      'rewriteMode': 'summarize',
      'language': 'en-US',
      'remoteModelId': 'whisper-small',
      'remoteAudioConsentVersion': 1,
      'systemRecognitionConsentVersion': 1,
    });

    expect(settings.enabled, isTrue);
    expect(settings.location, MobileAiDictationLocation.thisDevice);
    expect(settings.engine, MobileAiDictationEngine.systemRecognition);
    expect(settings.rewriteMode, MobileAiDictationRewriteMode.summarize);
    expect(settings.language, 'en-US');
    expect(settings.remoteModelId, 'whisper-small');
    expect(settings.remoteAudioConsentVersion, 1);
    expect(settings.systemRecognitionConsentVersion, 1);
  });

  test('migrates the legacy local Whisper engine and model id', () {
    final settings = MobileAiDictationSettings.fromJson(<String, Object?>{
      'enabled': true,
      'engine': 'localWhisper',
      'localModelId': 'whisper-cpp-base',
    });

    expect(settings.location, MobileAiDictationLocation.thisDevice);
    expect(settings.engine, MobileAiDictationEngine.whisper);
    expect(settings.localModelId, 'whisper-base');
  });

  test('normalizes paired-device settings to Whisper', () {
    final settings = MobileAiDictationSettings.fromJson(<String, Object?>{
      'location': 'pairedDevice',
      'engine': 'systemRecognition',
    });

    expect(settings.location, MobileAiDictationLocation.pairedDevice);
    expect(settings.engine, MobileAiDictationEngine.whisper);
  });

  test('preserves remote providers on the paired runtime', () {
    final openAi = MobileAiDictationSettings.fromJson(<String, Object?>{
      'location': 'pairedDevice',
      'engine': 'openAiCompatible',
      'providerBaseUrl': 'https://speech.example.test/v1',
      'providerModel': 'speech-model',
      'providerTimeoutSeconds': 120,
    });
    final codex = MobileAiDictationSettings.fromJson(<String, Object?>{
      'location': 'pairedDevice',
      'engine': 'codexSubscription',
      'codexRealtimeModel': 'realtime-model',
    });

    expect(openAi.engine, MobileAiDictationEngine.openAiCompatible);
    expect(openAi.providerModel, 'speech-model');
    expect(openAi.providerTimeoutSeconds, 120);
    expect(codex.engine, MobileAiDictationEngine.codexSubscription);
    expect(codex.codexRealtimeModel, 'realtime-model');
  });

  test('normalizes direct Codex to local Whisper', () {
    final settings = MobileAiDictationSettings.fromJson(<String, Object?>{
      'location': 'thisDevice',
      'engine': 'codexSubscription',
    });

    expect(settings.engine, MobileAiDictationEngine.whisper);
  });
}
