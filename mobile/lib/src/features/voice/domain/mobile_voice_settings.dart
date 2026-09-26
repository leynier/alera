class const MobileVoiceSettings({
  this.homeAgentProfileId,
  this.pipeline = MobileVoicePipeline.chained,
  this.sttProvider = MobileVoiceSttProvider.localWhisper,
  this.ttsProvider = MobileVoiceTtsProvider.geminiFlashTts,
  this.realtimeProvider = MobileVoiceRealtimeProvider.geminiFlashLive,
  this.ttsVoice,
  this.ackWhileThinking = false,
}) {
  factory fromJson(Map<String, Object?> json) {
    return MobileVoiceSettings(
      homeAgentProfileId: json['homeAgentProfileId'] as String?,
      pipeline: MobileVoicePipeline.fromJson(json['pipeline']),
      sttProvider: MobileVoiceSttProvider.fromJson(json['sttProvider']),
      ttsProvider: MobileVoiceTtsProvider.fromJson(json['ttsProvider']),
      realtimeProvider: MobileVoiceRealtimeProvider.fromJson(
        json['realtimeProvider'],
      ),
      ttsVoice: json['ttsVoice'] as String?,
      ackWhileThinking: json['ackWhileThinking'] == true,
    );
  }

  final String? homeAgentProfileId;
  final MobileVoicePipeline pipeline;
  final MobileVoiceSttProvider sttProvider;
  final MobileVoiceTtsProvider ttsProvider;
  final MobileVoiceRealtimeProvider realtimeProvider;
  final String? ttsVoice;
  final bool ackWhileThinking;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'homeAgentProfileId': homeAgentProfileId,
      'pipeline': pipeline.wireName,
      'sttProvider': sttProvider.wireName,
      'ttsProvider': ttsProvider.wireName,
      'realtimeProvider': realtimeProvider.wireName,
      'ttsVoice': ttsVoice,
      'ackWhileThinking': ackWhileThinking,
    };
  }

  MobileVoiceSettings copyWith({
    String? homeAgentProfileId,
    bool clearHomeAgentProfileId = false,
    MobileVoicePipeline? pipeline,
    MobileVoiceSttProvider? sttProvider,
    MobileVoiceTtsProvider? ttsProvider,
    MobileVoiceRealtimeProvider? realtimeProvider,
    String? ttsVoice,
    bool clearTtsVoice = false,
    bool? ackWhileThinking,
  }) {
    return MobileVoiceSettings(
      homeAgentProfileId: clearHomeAgentProfileId
          ? null
          : homeAgentProfileId ?? this.homeAgentProfileId,
      pipeline: pipeline ?? this.pipeline,
      sttProvider: sttProvider ?? this.sttProvider,
      ttsProvider: ttsProvider ?? this.ttsProvider,
      realtimeProvider: realtimeProvider ?? this.realtimeProvider,
      ttsVoice: clearTtsVoice ? null : ttsVoice ?? this.ttsVoice,
      ackWhileThinking: ackWhileThinking ?? this.ackWhileThinking,
    );
  }
}

enum MobileVoicePipeline {
  chained('chained', 'Chained STT + TTS'),
  realtime('realtime', 'Realtime speech-to-speech');

  MobileVoicePipeline(this.wireName, this.label);

  final String wireName;
  final String label;

  static MobileVoicePipeline fromJson(Object? value) {
    return MobileVoicePipeline.values.firstWhere(
      (item) => item.wireName == value,
      orElse: () => MobileVoicePipeline.chained,
    );
  }
}

enum MobileVoiceSttProvider {
  localWhisper('localWhisper', 'Local Whisper'),
  geminiTranscribeLive('geminiTranscribeLive', 'Gemini transcribe'),
  openAiCompatible('openAiCompatible', 'OpenAI-compatible'),
  codexRealtime('codexRealtime', 'Codex realtime');

  MobileVoiceSttProvider(this.wireName, this.label);

  final String wireName;
  final String label;

  static const List<MobileVoiceSttProvider> mobileChoices =
      <MobileVoiceSttProvider>[
        localWhisper,
        geminiTranscribeLive,
        openAiCompatible,
      ];

  static MobileVoiceSttProvider fromJson(Object? value) {
    return MobileVoiceSttProvider.values.firstWhere(
      (item) => item.wireName == value,
      orElse: () => MobileVoiceSttProvider.localWhisper,
    );
  }
}

enum MobileVoiceTtsProvider {
  geminiFlashTts('geminiFlashTts', 'Gemini Flash TTS'),
  openAiTts('openAiTts', 'OpenAI TTS');

  MobileVoiceTtsProvider(this.wireName, this.label);

  final String wireName;
  final String label;

  static MobileVoiceTtsProvider fromJson(Object? value) {
    return MobileVoiceTtsProvider.values.firstWhere(
      (item) => item.wireName == value,
      orElse: () => MobileVoiceTtsProvider.geminiFlashTts,
    );
  }
}

enum MobileVoiceRealtimeProvider {
  geminiFlashLive('geminiFlashLive', 'Gemini Live'),
  gptRealtimeMini('gptRealtimeMini', 'GPT Realtime Mini'),
  gptRealtime('gptRealtime', 'GPT Realtime'),
  gptLive1('gptLive1', 'GPT Live');

  MobileVoiceRealtimeProvider(this.wireName, this.label);

  final String wireName;
  final String label;

  static MobileVoiceRealtimeProvider fromJson(Object? value) {
    return MobileVoiceRealtimeProvider.values.firstWhere(
      (item) => item.wireName == value,
      orElse: () => MobileVoiceRealtimeProvider.geminiFlashLive,
    );
  }
}

class const MobileVoiceCredentialStatus({
  this.geminiConfigured = false,
  this.openaiConfigured = false,
}) {
  factory fromJson(Map<String, Object?> json) {
    return MobileVoiceCredentialStatus(
      geminiConfigured: json['geminiConfigured'] == true,
      openaiConfigured: json['openaiConfigured'] == true,
    );
  }

  final bool geminiConfigured;
  final bool openaiConfigured;
}
