import 'package:dart_mappable/dart_mappable.dart';

part 'ai_dictation_settings.mapper.dart';

@MappableEnum()
enum AiDictationProviderPolicy { localOnly, localPreferred }

@MappableEnum()
enum AiDictationFallbackProvider { openAiCompatible }

@MappableEnum()
enum AiDictationTranscriptionEngine {
  localWhisper,
  codexSubscription,
  openAiCompatible,
  systemOnDevice,
  systemRecognition,
}

@MappableEnum()
enum AiDictationRewriteMode { off, cleanUp, summarize }

@MappableClass()
class AiDictationSettings with AiDictationSettingsMappable {
  const AiDictationSettings({
    this.enabled = false,
    this.transcriptionEngine = AiDictationTranscriptionEngine.localWhisper,
    this.rewriteMode = AiDictationRewriteMode.off,
    this.providerPolicy = AiDictationProviderPolicy.localPreferred,
    this.language,
    this.localModelId = 'whisper-cpp-base',
    this.hostFallbackEnabled = true,
    this.providerFallbackEnabled = false,
    this.remoteBaseUrl = 'https://api.openai.com/v1',
    this.remoteModel = 'gpt-4o-mini-transcribe',
    this.codexRealtimeModel,
    this.remoteProvider = AiDictationFallbackProvider.openAiCompatible,
    this.timeoutSeconds = 60,
    this.remoteConsentVersion,
    this.systemRecognitionConsentVersion,
  });

  final bool enabled;
  final AiDictationTranscriptionEngine transcriptionEngine;
  final AiDictationRewriteMode rewriteMode;
  final AiDictationProviderPolicy providerPolicy;
  final String? language;
  final String localModelId;
  final bool hostFallbackEnabled;
  final bool providerFallbackEnabled;
  final String? remoteBaseUrl;
  final String? remoteModel;
  final String? codexRealtimeModel;
  final AiDictationFallbackProvider remoteProvider;
  final int timeoutSeconds;
  final int? remoteConsentVersion;
  final int? systemRecognitionConsentVersion;

  static const AiDictationSettings defaults = AiDictationSettings();

  factory AiDictationSettings.fromJson(Map<String, Object?> json) =>
      AiDictationSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}
