import 'package:alera/src/features/voice/domain/voice_activity_detector.dart';
import 'package:alera/src/features/voice/domain/voice_session_status.dart';
import 'package:alera/src/features/voice/domain/voice_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('voice session status decodes the host payload', () {
    final status = VoiceSessionStatus.fromJson(<String, Object?>{
      'homeWorkspaceId': 'alera-home',
      'phase': 'thinking',
      'queuedTurnCount': 2,
      'realtime': true,
      'captureOwnerClientId': 7,
    });

    expect(status.homeWorkspaceId, 'alera-home');
    expect(status.phase, VoiceSessionPhase.thinking);
    expect(status.queuedTurnCount, 2);
    expect(status.realtime, isTrue);
    expect(status.captureOwnerClientId, 7);
    expect(VoiceSessionStatus.empty.phase, VoiceSessionPhase.idle);
  });

  test('voice settings decode with defaults for omitted fields', () {
    final settings = VoiceSettings.fromJson(<String, Object?>{
      'pipeline': 'realtime',
      'realtimeProvider': 'gptRealtime',
    });

    expect(settings.pipeline, VoicePipeline.realtime);
    expect(settings.realtimeProvider, VoiceRealtimeProvider.gptRealtime);
    expect(settings.sttProvider, VoiceSettings.defaults.sttProvider);
    expect(settings.ttsProvider, VoiceTtsProvider.geminiFlashTts);
  });

  test('credential status defaults to nothing configured', () {
    const status = VoiceCredentialStatus();
    const saved = VoiceCredentialStatus(geminiConfigured: true);

    expect(status.geminiConfigured, isFalse);
    expect(status.openaiConfigured, isFalse);
    expect(saved.geminiConfigured, isTrue);
  });

  test('reset drops a turn in progress', () {
    final detector = VoiceActivityDetector(startFrames: 1);
    expect(
      detector.observe(0.5, speaking: false),
      VoiceActivityEvent.speechStart,
    );
    expect(detector.capturing, isTrue);

    detector.reset();

    expect(detector.capturing, isFalse);
    expect(detector.observe(0.001, speaking: false), VoiceActivityEvent.none);
  });
}
