enum MobileAiDictationEngine { systemOnDevice, systemRecognition }

enum MobileAiDictationRewriteMode { off, cleanUp, summarize }

class MobileAiDictationSettings {
  const MobileAiDictationSettings({
    this.enabled = false,
    this.engine = MobileAiDictationEngine.systemOnDevice,
    this.rewriteMode = MobileAiDictationRewriteMode.off,
    this.language,
    this.systemRecognitionConsentVersion,
  });

  final bool enabled;
  final MobileAiDictationEngine engine;
  final MobileAiDictationRewriteMode rewriteMode;
  final String? language;
  final int? systemRecognitionConsentVersion;

  MobileAiDictationSettings copyWith({
    bool? enabled,
    MobileAiDictationEngine? engine,
    MobileAiDictationRewriteMode? rewriteMode,
    String? language,
    int? systemRecognitionConsentVersion,
    bool clearLanguage = false,
    bool clearConsent = false,
  }) => MobileAiDictationSettings(
    enabled: enabled ?? this.enabled,
    engine: engine ?? this.engine,
    rewriteMode: rewriteMode ?? this.rewriteMode,
    language: clearLanguage ? null : language ?? this.language,
    systemRecognitionConsentVersion: clearConsent
        ? null
        : systemRecognitionConsentVersion ??
              this.systemRecognitionConsentVersion,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'engine': engine.name,
    'rewriteMode': rewriteMode.name,
    'language': language,
    'systemRecognitionConsentVersion': systemRecognitionConsentVersion,
  };

  factory MobileAiDictationSettings.fromJson(Map<String, Object?> json) {
    final engineName = json['engine']?.toString();
    final rewriteName = json['rewriteMode']?.toString();
    return MobileAiDictationSettings(
      enabled: json['enabled'] == true,
      engine: MobileAiDictationEngine.values.firstWhere(
        (value) => value.name == engineName,
        orElse: () => MobileAiDictationEngine.systemOnDevice,
      ),
      rewriteMode: MobileAiDictationRewriteMode.values.firstWhere(
        (value) => value.name == rewriteName,
        orElse: () => MobileAiDictationRewriteMode.off,
      ),
      language: json['language'] as String?,
      systemRecognitionConsentVersion:
          (json['systemRecognitionConsentVersion'] as num?)?.toInt(),
    );
  }
}
