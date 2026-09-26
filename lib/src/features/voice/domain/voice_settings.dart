import 'package:dart_mappable/dart_mappable.dart';

part 'voice_settings.mapper.dart';

@MappableEnum()
enum VoicePipeline { chained, realtime }

@MappableEnum()
enum VoiceSttProvider {
  localWhisper,
  geminiTranscribeLive,
  openAiCompatible,
  codexRealtime,
}

@MappableEnum()
enum VoiceTtsProvider { geminiFlashTts, openAiTts }

@MappableEnum()
enum VoiceRealtimeProvider {
  geminiFlashLive,
  gptRealtimeMini,
  gptRealtime,
  gptLive1,
}

@MappableClass()
class const VoiceSettings({
  this.homeAgentProfileId,
  this.pipeline = VoicePipeline.chained,
  this.sttProvider = VoiceSttProvider.localWhisper,
  this.ttsProvider = VoiceTtsProvider.geminiFlashTts,
  this.realtimeProvider = VoiceRealtimeProvider.geminiFlashLive,
  this.ttsVoice,
  this.ackWhileThinking = false,
}) with VoiceSettingsMappable {
  final String? homeAgentProfileId;
  final VoicePipeline pipeline;
  final VoiceSttProvider sttProvider;
  final VoiceTtsProvider ttsProvider;
  final VoiceRealtimeProvider realtimeProvider;
  final String? ttsVoice;
  final bool ackWhileThinking;

  static const VoiceSettings defaults = VoiceSettings();

  factory fromJson(Map<String, Object?> json) =>
      VoiceSettingsMapper.fromMap(Map<String, dynamic>.from(json));
}

class const VoiceCredentialStatus({
  this.geminiConfigured = false,
  this.openaiConfigured = false,
}) {
  final bool geminiConfigured;
  final bool openaiConfigured;
}
