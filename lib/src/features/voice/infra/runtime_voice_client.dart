import 'dart:convert';

import 'package:alera/src/features/voice/domain/voice_session_status.dart';
import 'package:alera/src/features/voice/domain/voice_settings.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

class RuntimeVoiceClient({required this.client, required this.capabilities}) {
  final RuntimeHostClient client;
  final RuntimeHostCapabilityClient capabilities;

  Future<bool> isSupported() {
    return capabilities.supportsRuntimeCapability(
      aleraRuntimeHostVoiceHomeAgentCapability,
    );
  }

  Future<VoiceSessionStatus> ensure() async {
    return _statusFrom(client.runtimeRequest('voice.ensure'));
  }

  Future<VoiceSessionStatus> status() async {
    return _statusFrom(client.runtimeRequest('voice.status'));
  }

  Future<VoiceSessionStatus> start() async {
    return _statusFrom(client.runtimeRequest('voice.start'));
  }

  Future<VoiceSessionStatus> stop() async {
    return _statusFrom(client.runtimeRequest('voice.stop'));
  }

  Future<VoiceSessionStatus> speak(String text) async {
    return _statusFrom(
      client.runtimeRequest('voice.speak', <String, Object?>{'text': text}),
    );
  }

  Future<void> submitTurn(
    String text, {
    bool cancelHome = false,
    List<int>? pcm16k,
  }) async {
    await client.runtimeRequest('voice.turn', <String, Object?>{
      if (text.trim().isNotEmpty) 'text': text,
      if (pcm16k == null) 'cancelHome': cancelHome,
      if (pcm16k != null) 'audioBase64': base64Encode(pcm16k),
    }, const Duration(seconds: 60));
  }

  Future<List<int>> synthesize(
    String text, {
    String? provider,
    String? voice,
  }) async {
    final payload = await client.runtimeRequest(
      'voice.synthesize',
      <String, Object?>{'text': text, 'provider': ?provider, 'voice': ?voice},
      const Duration(seconds: 60),
    );
    if (payload is! Map) {
      return const <int>[];
    }
    final encoded = payload['audioBase64'];
    if (encoded is! String || encoded.isEmpty) {
      return const <int>[];
    }
    return base64Decode(encoded);
  }

  Future<void> markSpoken(
    String text, {
    int? id,
    bool failed = false,
    String? error,
  }) async {
    await client.runtimeRequest('voice.spoken', <String, Object?>{
      'text': text,
      'id': ?id,
      if (failed) 'failed': true,
      if (error != null && error.isNotEmpty) 'error': error,
    });
  }

  Future<void> sendAudio(List<int> pcm16k) async {
    await client.runtimeRequest('voice.audio', <String, Object?>{
      'audioBase64': base64Encode(pcm16k),
    });
  }

  Future<void> sendActivity(String phase) async {
    await client.runtimeRequest('voice.activity', <String, Object?>{
      'phase': phase,
    });
  }

  Future<VoiceCredentialStatus> credentialStatus() async {
    final payload = await client.runtimeRequest(
      'voice.credentials.status',
      const <String, Object?>{},
    );
    if (payload is! Map) {
      return const VoiceCredentialStatus();
    }
    return VoiceCredentialStatus(
      geminiConfigured: payload['geminiConfigured'] == true,
      openaiConfigured: payload['openaiConfigured'] == true,
    );
  }

  Future<VoiceCredentialStatus> saveCredentials({
    String? geminiToken,
    String? openaiToken,
  }) async {
    final payload = await client.runtimeRequest(
      'voice.credentials.save',
      <String, Object?>{
        'geminiToken': ?geminiToken,
        'openaiToken': ?openaiToken,
      },
    );
    if (payload is! Map) {
      return const VoiceCredentialStatus();
    }
    return VoiceCredentialStatus(
      geminiConfigured: payload['geminiConfigured'] == true,
      openaiConfigured: payload['openaiConfigured'] == true,
    );
  }

  Future<VoiceCredentialStatus> clearCredentials({String? provider}) async {
    final payload = await client.runtimeRequest(
      'voice.credentials.clear',
      <String, Object?>{'provider': ?provider},
    );
    if (payload is! Map) {
      return const VoiceCredentialStatus();
    }
    return VoiceCredentialStatus(
      geminiConfigured: payload['geminiConfigured'] == true,
      openaiConfigured: payload['openaiConfigured'] == true,
    );
  }

  Future<VoiceSessionStatus> _statusFrom(Future<Object?> request) async {
    final payload = await request;
    if (payload is! Map) {
      return VoiceSessionStatus.empty;
    }
    return VoiceSessionStatus.fromJson(Map<String, Object?>.from(payload));
  }
}
