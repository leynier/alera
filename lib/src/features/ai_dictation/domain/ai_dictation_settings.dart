import 'package:dart_mappable/dart_mappable.dart';

part 'ai_dictation_settings.mapper.dart';

@MappableEnum()
enum AiDictationProviderPolicy { localOnly, localPreferred }

@MappableClass()
class AiDictationSettings with AiDictationSettingsMappable {
  const AiDictationSettings({
    this.enabled = false,
    this.providerPolicy = AiDictationProviderPolicy.localPreferred,
    this.language,
    this.localModelId = 'whisper-cpp-base',
    this.remoteBaseUrl,
    this.remoteModel,
    this.timeoutSeconds = 60,
    this.remoteConsentVersion,
  });

  final bool enabled;
  final AiDictationProviderPolicy providerPolicy;
  final String? language;
  final String localModelId;
  final String? remoteBaseUrl;
  final String? remoteModel;
  final int timeoutSeconds;
  final int? remoteConsentVersion;

  static const AiDictationSettings defaults = AiDictationSettings();

  factory AiDictationSettings.fromJson(Map<String, Object?> json) =>
      AiDictationSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}
