import 'dart:async';

import 'package:alera/src/features/ai_dictation/domain/ai_dictation_request.dart';
import 'package:alera/src/features/ai_dictation/infra/runtime_ai_dictation_credential_store.dart';
import 'package:alera/src/features/ai_dictation/infra/runtime_ai_dictation_provider.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('sends OpenAI-compatible configuration without an API token', () async {
    final client = _FakeRuntimeHostClient(<String, Object?>{
      'text': 'hello',
      'providerId': 'openai-compatible',
      'durationMillis': 1000,
      'elapsedMillis': 25,
    });
    final provider = RuntimeAiDictationProvider(client);

    final result = await provider.transcribe(
      const AiDictationRequest(
        requestId: 'request-1',
        audioPath: '/tmp/audio.wav',
        remoteEngine: .openAiCompatible,
        providerBaseUrl: 'https://api.example.test/v1',
        providerModel: 'speech-model',
        language: 'es',
        timeout: Duration(seconds: 30),
      ),
    );

    expect(client.lastType, 'aiDictation.transcribe');
    expect(client.lastPayload, <String, Object?>{
      'requestId': 'request-1',
      'audioPath': '/tmp/audio.wav',
      'engine': 'openAiCompatible',
      'baseUrl': 'https://api.example.test/v1',
      'modelId': 'speech-model',
      'language': 'es',
      'initialPrompt': null,
      'timeoutSeconds': 30,
    });
    expect(client.lastPayload, isNot(contains('token')));
    expect(result.text, 'hello');
    expect(result.providerId, 'openai-compatible');
  });

  test('uses Codex subscription engine and optional realtime model', () async {
    final client = _FakeRuntimeHostClient(<String, Object?>{
      'text': 'subscription transcript',
      'providerId': 'codex-subscription',
    });
    final provider = RuntimeAiDictationProvider(client);

    await provider.transcribe(
      const AiDictationRequest(
        requestId: 'request-2',
        audioPath: '/tmp/audio.wav',
        remoteEngine: .codexSubscription,
        providerModel: 'realtime-model',
      ),
    );

    expect(client.lastPayload?['engine'], 'codexSubscription');
    expect(client.lastPayload?['modelId'], 'realtime-model');
  });

  test('credential store sends tokens only to the save request', () async {
    final client = _FakeRuntimeHostClient(<String, Object?>{
      'configured': true,
    });
    final store = RuntimeAiDictationCredentialStore(client);

    final status = await store.status('https://api.example.test/v1');
    expect(status.configured, isTrue);
    expect(status.matchesBaseUrl, isFalse);
    await store.saveToken(
      ' secret-token ',
      baseUrl: 'https://api.example.test/v1',
    );

    expect(client.lastType, 'aiDictation.credentials.save');
    expect(client.lastPayload, <String, Object?>{
      'token': 'secret-token',
      'baseUrl': 'https://api.example.test/v1',
    });
  });

  test('credential store avoids new verbs on an older sidecar', () async {
    final client = _FakeRuntimeHostClient(
      const <String, Object?>{},
      supportsRemoteAiDictation: false,
    );
    final store = RuntimeAiDictationCredentialStore(client);

    final status = await store.status('https://api.example.test/v1');

    expect(status.supported, isFalse);
    expect(client.lastType, isNull);
  });
}

class _FakeRuntimeHostClient(
  final Object? response, {
  final bool supportsRemoteAiDictation = true,
}) implements RuntimeHostClient, RuntimeHostCapabilityClient {
  String? lastType;
  Map<String, Object?>? lastPayload;

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    lastType = type;
    lastPayload = payload;
    return response;
  }

  @override
  Future<bool> supportsRuntimeCapability(String capability) async =>
      capability == aleraRuntimeHostRemoteAiDictationCapability &&
      supportsRemoteAiDictation;
}
