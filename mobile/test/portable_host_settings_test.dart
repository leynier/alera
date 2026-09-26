import 'package:alera_mobile/src/features/settings/domain/portable_host_settings.dart';
import 'package:alera_mobile/src/features/voice/domain/mobile_voice_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('includes fx in the supported status integrations', () {
    expect(supportedAgentHooks, contains('fx'));
    expect(agentHookLabels['fx'], 'fx');

    final settings = PortableHostSettings.fromJson(<String, Object?>{
      'agentStatusHooks': <String, Object?>{'fx': true},
    });

    expect(settings.agentStatusHooks['fx'], isTrue);
  });

  test('parses voice settings with defaults when omitted', () {
    final settings = PortableHostSettings.fromJson(const <String, Object?>{});
    expect(settings.voice.pipeline, MobileVoicePipeline.chained);
    expect(settings.voice.sttProvider, MobileVoiceSttProvider.localWhisper);
    expect(settings.voice.ttsProvider, MobileVoiceTtsProvider.geminiFlashTts);
    expect(
      settings.voice.realtimeProvider,
      MobileVoiceRealtimeProvider.geminiFlashLive,
    );
    expect(settings.voice.ackWhileThinking, isFalse);
  });

  test('round-trips a voice settings patch', () {
    final settings = PortableHostSettings.fromJson(const <String, Object?>{
      'voice': <String, Object?>{
        'pipeline': 'realtime',
        'sttProvider': 'geminiTranscribeLive',
        'ttsProvider': 'openAiTts',
        'realtimeProvider': 'gptRealtimeMini',
        'ttsVoice': 'Kore',
        'homeAgentProfileId': 'codex',
        'ackWhileThinking': true,
      },
    });
    expect(settings.voice.pipeline, MobileVoicePipeline.realtime);
    expect(
      settings.voice.sttProvider,
      MobileVoiceSttProvider.geminiTranscribeLive,
    );
    expect(settings.voice.ttsProvider, MobileVoiceTtsProvider.openAiTts);
    expect(
      settings.voice.realtimeProvider,
      MobileVoiceRealtimeProvider.gptRealtimeMini,
    );
    expect(settings.voice.ttsVoice, 'Kore');
    expect(settings.voice.homeAgentProfileId, 'codex');
    expect(settings.voice.ackWhileThinking, isTrue);
    expect(settings.voice.toJson()['pipeline'], 'realtime');
  });
}
