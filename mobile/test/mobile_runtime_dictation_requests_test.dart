import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paired OpenAI sends provider config without a mobile token', () async {
    final client = _FakeMobileRuntimeDictationClient(<String>{
      aiDictationCapability,
      aiDictationModelsCapability,
      remoteAiDictationCapability,
    });

    await client.transcribeMobileAudio(
      requestId: 'runtime-openai-1',
      audio: <int>[1, 2, 3],
      engine: 'openAiCompatible',
      modelId: 'speech-model',
      baseUrl: 'https://speech.example.test/v1',
      timeoutSeconds: 30,
      language: 'es',
    );

    expect(client.lastType, 'mobile.aiDictation.transcribe');
    expect(client.lastPayload?['engine'], 'openAiCompatible');
    expect(client.lastPayload?['modelId'], 'speech-model');
    expect(
      client.lastPayload?['baseUrl'],
      'https://speech.example.test/v1',
    );
    expect(client.lastPayload, isNot(contains('token')));
  });

  test('paired remote provider requires the additive capability', () {
    final client = _FakeMobileRuntimeDictationClient(<String>{
      aiDictationCapability,
      aiDictationModelsCapability,
    });

    expect(
      () => client.transcribeMobileAudio(
        requestId: 'runtime-openai-2',
        audio: <int>[1],
        engine: 'openAiCompatible',
        modelId: 'speech-model',
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });
}

class _FakeMobileRuntimeDictationClient
    with MobileRuntimeDictationRequests {
  _FakeMobileRuntimeDictationClient(this.runtimeCapabilities);

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
    return <String, Object?>{'text': 'hello'};
  }
}
