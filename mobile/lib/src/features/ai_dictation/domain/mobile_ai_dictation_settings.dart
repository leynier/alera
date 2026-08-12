class MobileAiDictationSettings {
  const MobileAiDictationSettings({
    this.enabled = false,
    this.localModelId = 'whisper-base',
    this.hostFallbackEnabled = true,
    this.providerFallbackEnabled = false,
    this.providerBaseUrl = 'https://api.openai.com',
    this.providerModel = 'gpt-4o-mini-transcribe',
    this.language,
  });

  final bool enabled;
  final String localModelId;
  final bool hostFallbackEnabled;
  final bool providerFallbackEnabled;
  final String providerBaseUrl;
  final String providerModel;
  final String? language;

  MobileAiDictationSettings copyWith({
    bool? enabled,
    String? localModelId,
    bool? hostFallbackEnabled,
    bool? providerFallbackEnabled,
    String? providerBaseUrl,
    String? providerModel,
    String? language,
  }) => MobileAiDictationSettings(
    enabled: enabled ?? this.enabled,
    localModelId: localModelId ?? this.localModelId,
    hostFallbackEnabled: hostFallbackEnabled ?? this.hostFallbackEnabled,
    providerFallbackEnabled:
        providerFallbackEnabled ?? this.providerFallbackEnabled,
    providerBaseUrl: providerBaseUrl ?? this.providerBaseUrl,
    providerModel: providerModel ?? this.providerModel,
    language: language ?? this.language,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'localModelId': localModelId,
    'hostFallbackEnabled': hostFallbackEnabled,
    'providerFallbackEnabled': providerFallbackEnabled,
    'providerBaseUrl': providerBaseUrl,
    'providerModel': providerModel,
    'language': language,
  };

  factory MobileAiDictationSettings.fromJson(Map<String, Object?> json) =>
      MobileAiDictationSettings(
        enabled: json['enabled'] == true,
        localModelId: json['localModelId'] as String? ?? 'whisper-base',
        hostFallbackEnabled: json['hostFallbackEnabled'] != false,
        providerFallbackEnabled: json['providerFallbackEnabled'] == true,
        providerBaseUrl:
            json['providerBaseUrl'] as String? ?? 'https://api.openai.com',
        providerModel:
            json['providerModel'] as String? ?? 'gpt-4o-mini-transcribe',
        language: json['language'] as String?,
      );
}
