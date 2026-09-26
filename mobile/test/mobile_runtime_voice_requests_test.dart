import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'voice credential RPCs use mobile aliases and never echo tokens',
    () async {
      final client = _FakeMobileRuntimeVoiceClient(<String>{
        voiceHomeAgentCapability,
      });

      await client.voiceCredentialStatus();
      expect(client.lastType, 'mobile.voice.credentials.status');

      await client.saveVoiceCredentials(geminiToken: 'AIza-secret');
      expect(client.lastType, 'mobile.voice.credentials.save');
      expect(client.lastPayload?['geminiToken'], 'AIza-secret');
      expect(client.lastPayload, isNot(contains('openaiToken')));

      await client.clearVoiceCredentials(provider: 'openai');
      expect(client.lastType, 'mobile.voice.credentials.clear');
      expect(client.lastPayload?['provider'], 'openai');
    },
  );

  test('voice credential RPCs require the home agent capability', () {
    final client = _FakeMobileRuntimeVoiceClient(<String>{});
    expect(client.voiceCredentialStatus, throwsA(isA<UnsupportedError>()));
  });
}

class _FakeMobileRuntimeVoiceClient(this.runtimeCapabilities)
    with MobileRuntimeVoiceRequests {
  @override
  final Set<String> runtimeCapabilities;
  String? lastType;
  Map<String, Object?>? lastPayload;

  @override
  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    lastType = type;
    lastPayload = payload;
    return const <String, Object?>{
      'geminiConfigured': true,
      'openaiConfigured': false,
    };
  }
}
