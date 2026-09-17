import 'package:alera/src/features/voice/domain/voice_activity_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('speech starts after enough loud frames and ends after silence', () {
    final detector = VoiceActivityDetector(startFrames: 2, endSilenceFrames: 3);
    expect(detector.observe(0.01, speaking: false), VoiceActivityEvent.none);
    expect(detector.observe(0.2, speaking: false), VoiceActivityEvent.none);
    expect(
      detector.observe(0.2, speaking: false),
      VoiceActivityEvent.speechStart,
    );
    expect(detector.observe(0.2, speaking: false), VoiceActivityEvent.none);
    expect(detector.observe(0.001, speaking: false), VoiceActivityEvent.none);
    expect(detector.observe(0.001, speaking: false), VoiceActivityEvent.none);
    expect(
      detector.observe(0.001, speaking: false),
      VoiceActivityEvent.speechEnd,
    );
  });

  test('barge-in requires a louder RMS while the speaker is playing', () {
    final detector = VoiceActivityDetector(startFrames: 1, bargeInRms: 0.2);
    expect(detector.observe(0.05, speaking: true), VoiceActivityEvent.none);
    expect(
      detector.observe(0.4, speaking: true),
      VoiceActivityEvent.speechStart,
    );
  });
}
