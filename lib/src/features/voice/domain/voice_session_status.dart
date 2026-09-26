import 'package:dart_mappable/dart_mappable.dart';

part 'voice_session_status.mapper.dart';

@MappableEnum()
enum VoiceSessionPhase { idle, listening, thinking, speaking }

@MappableClass()
class const VoiceSessionStatus({
  this.homeWorkspaceId,
  this.homeProjectId,
  this.homeDir,
  this.homeTabId,
  this.homeSessionId,
  this.phase = VoiceSessionPhase.idle,
  this.speaking = false,
  this.queuedSpeakCount = 0,
  this.queuedTurnCount = 0,
  this.lastSpoken,
  this.lastError,
  this.realtime = false,
  this.sessionGeneration = 0,
  this.captureOwnerClientId,
}) with VoiceSessionStatusMappable {
  final String? homeWorkspaceId;
  final String? homeProjectId;
  final String? homeDir;
  final String? homeTabId;
  final String? homeSessionId;
  final VoiceSessionPhase phase;
  final bool speaking;
  final int queuedSpeakCount;
  final int queuedTurnCount;
  final String? lastSpoken;
  final String? lastError;
  final bool realtime;
  final int sessionGeneration;
  final int? captureOwnerClientId;

  static const VoiceSessionStatus empty = VoiceSessionStatus();

  factory fromJson(Map<String, Object?> json) =>
      VoiceSessionStatusMapper.fromMap(Map<String, dynamic>.from(json));
}
