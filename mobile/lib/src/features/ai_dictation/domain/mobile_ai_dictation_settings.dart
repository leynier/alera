enum MobileAiDictationLocation { thisDevice, pairedDevice }

enum MobileAiDictationEngine {
  whisper,
  openAiCompatible,
  codexSubscription,
  systemOnDevice,
  systemRecognition,
}

enum MobileAiDictationRewriteMode { off, cleanUp, summarize }

class MobileAiDictationSettings {
  const MobileAiDictationSettings({
    this.enabled = false,
    this.location = MobileAiDictationLocation.thisDevice,
    this.engine = MobileAiDictationEngine.systemOnDevice,
    this.rewriteMode = MobileAiDictationRewriteMode.off,
    this.language,
    this.localModelId = 'whisper-base',
    this.remoteModelId = 'whisper-base',
    this.providerBaseUrl = 'https://api.openai.com/v1',
    this.providerModel = 'gpt-4o-mini-transcribe',
    this.codexRealtimeModel,
    this.providerTimeoutSeconds = 60,
    this.remoteAudioConsentVersion,
    this.systemRecognitionConsentVersion,
  });

  final bool enabled;
  final MobileAiDictationLocation location;
  final MobileAiDictationEngine engine;
  final MobileAiDictationRewriteMode rewriteMode;
  final String? language;
  final String localModelId;
  final String remoteModelId;
  final String providerBaseUrl;
  final String providerModel;
  final String? codexRealtimeModel;
  final int providerTimeoutSeconds;
  final int? remoteAudioConsentVersion;
  final int? systemRecognitionConsentVersion;

  bool get usesWhisper => engine == MobileAiDictationEngine.whisper;
  bool get sendsAudioToPairedDevice =>
      location == MobileAiDictationLocation.pairedDevice;
  bool get sendsAudioToProvider =>
      engine == MobileAiDictationEngine.openAiCompatible ||
      engine == MobileAiDictationEngine.codexSubscription;
  bool get requiresRemoteAudioConsent =>
      sendsAudioToPairedDevice || sendsAudioToProvider;

  MobileAiDictationSettings copyWith({
    bool? enabled,
    MobileAiDictationLocation? location,
    MobileAiDictationEngine? engine,
    MobileAiDictationRewriteMode? rewriteMode,
    String? language,
    String? localModelId,
    String? remoteModelId,
    String? providerBaseUrl,
    String? providerModel,
    String? codexRealtimeModel,
    int? providerTimeoutSeconds,
    int? remoteAudioConsentVersion,
    int? systemRecognitionConsentVersion,
    bool clearLanguage = false,
    bool clearRemoteConsent = false,
    bool clearSystemConsent = false,
    bool clearCodexRealtimeModel = false,
  }) => MobileAiDictationSettings(
    enabled: enabled ?? this.enabled,
    location: location ?? this.location,
    engine: engine ?? this.engine,
    rewriteMode: rewriteMode ?? this.rewriteMode,
    language: clearLanguage ? null : language ?? this.language,
    localModelId: localModelId ?? this.localModelId,
    remoteModelId: remoteModelId ?? this.remoteModelId,
    providerBaseUrl: providerBaseUrl ?? this.providerBaseUrl,
    providerModel: providerModel ?? this.providerModel,
    codexRealtimeModel: clearCodexRealtimeModel
        ? null
        : codexRealtimeModel ?? this.codexRealtimeModel,
    providerTimeoutSeconds:
        providerTimeoutSeconds ?? this.providerTimeoutSeconds,
    remoteAudioConsentVersion: clearRemoteConsent
        ? null
        : remoteAudioConsentVersion ?? this.remoteAudioConsentVersion,
    systemRecognitionConsentVersion: clearSystemConsent
        ? null
        : systemRecognitionConsentVersion ??
              this.systemRecognitionConsentVersion,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'location': location.name,
    'engine': engine.name,
    'rewriteMode': rewriteMode.name,
    'language': language,
    'localModelId': localModelId,
    'remoteModelId': remoteModelId,
    'providerBaseUrl': providerBaseUrl,
    'providerModel': providerModel,
    'codexRealtimeModel': codexRealtimeModel,
    'providerTimeoutSeconds': providerTimeoutSeconds,
    'remoteAudioConsentVersion': remoteAudioConsentVersion,
    'systemRecognitionConsentVersion': systemRecognitionConsentVersion,
  };

  factory MobileAiDictationSettings.fromJson(Map<String, Object?> json) {
    final engineName = json['engine']?.toString();
    final legacyWhisper = engineName == 'localWhisper';
    final location = MobileAiDictationLocation.values.firstWhere(
      (value) => value.name == json['location'],
      orElse: () => MobileAiDictationLocation.thisDevice,
    );
    final persistedEngine = MobileAiDictationEngine.values.firstWhere(
      (value) => value.name == engineName,
      orElse: () => legacyWhisper
          ? MobileAiDictationEngine.whisper
          : MobileAiDictationEngine.systemOnDevice,
    );
    return MobileAiDictationSettings(
      enabled: json['enabled'] == true,
      location: location,
      engine:
          location == MobileAiDictationLocation.pairedDevice &&
              (persistedEngine == MobileAiDictationEngine.systemOnDevice ||
                  persistedEngine == MobileAiDictationEngine.systemRecognition)
          ? MobileAiDictationEngine.whisper
          : location == MobileAiDictationLocation.thisDevice &&
                persistedEngine == MobileAiDictationEngine.codexSubscription
          ? MobileAiDictationEngine.whisper
          : persistedEngine,
      rewriteMode: MobileAiDictationRewriteMode.values.firstWhere(
        (value) => value.name == json['rewriteMode'],
        orElse: () => MobileAiDictationRewriteMode.off,
      ),
      language: json['language'] as String?,
      localModelId: json['localModelId']?.toString() == 'whisper-cpp-base'
          ? 'whisper-base'
          : json['localModelId']?.toString() ?? 'whisper-base',
      remoteModelId: json['remoteModelId']?.toString() ?? 'whisper-base',
      providerBaseUrl:
          json['providerBaseUrl']?.toString() ?? 'https://api.openai.com/v1',
      providerModel:
          json['providerModel']?.toString() ?? 'gpt-4o-mini-transcribe',
      codexRealtimeModel: json['codexRealtimeModel']?.toString(),
      providerTimeoutSeconds:
          (json['providerTimeoutSeconds'] as num?)?.toInt() ?? 60,
      remoteAudioConsentVersion: (json['remoteAudioConsentVersion'] as num?)
          ?.toInt(),
      systemRecognitionConsentVersion:
          (json['systemRecognitionConsentVersion'] as num?)?.toInt(),
    );
  }
}
