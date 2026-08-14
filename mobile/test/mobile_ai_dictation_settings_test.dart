import 'package:alera_mobile/src/features/ai_dictation/domain/mobile_ai_dictation_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to opt-in on-device dictation without transcript rewriting', () {
    const settings = MobileAiDictationSettings();

    expect(settings.enabled, isFalse);
    expect(settings.engine, MobileAiDictationEngine.systemOnDevice);
    expect(settings.rewriteMode, MobileAiDictationRewriteMode.off);
    expect(settings.systemRecognitionConsentVersion, isNull);
  });

  test('decodes persisted recognition and processing choices', () {
    final settings = MobileAiDictationSettings.fromJson(<String, Object?>{
      'enabled': true,
      'engine': 'systemRecognition',
      'rewriteMode': 'summarize',
      'language': 'en-US',
      'systemRecognitionConsentVersion': 1,
    });

    expect(settings.enabled, isTrue);
    expect(settings.engine, MobileAiDictationEngine.systemRecognition);
    expect(settings.rewriteMode, MobileAiDictationRewriteMode.summarize);
    expect(settings.language, 'en-US');
    expect(settings.systemRecognitionConsentVersion, 1);
  });
}
