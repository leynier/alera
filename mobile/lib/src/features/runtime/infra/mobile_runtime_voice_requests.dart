part of 'mobile_runtime_client.dart';

mixin MobileRuntimeVoiceRequests {
  Set<String> get runtimeCapabilities;
  Future<void> _voiceSessionShutdown = Future<void>.value();

  bool get supportsVoiceHomeAgent =>
      runtimeCapabilities.contains(voiceHomeAgentCapability);

  Future<void> awaitVoiceSessionShutdown() => _voiceSessionShutdown;

  void registerVoiceSessionShutdown(Future<void> shutdown) {
    _voiceSessionShutdown = _voiceSessionShutdown
        .then((_) => shutdown)
        .catchError((Object _) {});
  }

  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]);

  Future<Map<String, Object?>> voiceStatus() {
    _requireVoice();
    return requestMap('mobile.voice.status');
  }

  Future<Map<String, Object?>?> startVoice({
    bool Function()? stillValid,
  }) async {
    _requireVoice();
    await awaitVoiceSessionShutdown();
    if (stillValid != null && !stillValid()) {
      return null;
    }
    return requestMap('mobile.voice.start');
  }

  Future<Map<String, Object?>> stopVoice() {
    _requireVoice();
    return requestMap('mobile.voice.stop');
  }

  Future<Map<String, Object?>> submitVoiceTurn(
    String text, {
    bool cancelHome = false,
    List<int>? pcm16k,
  }) {
    _requireVoice();
    return requestMap('mobile.voice.turn', <String, Object?>{
      if (text.trim().isNotEmpty) 'text': text,
      if (pcm16k == null) 'cancelHome': cancelHome,
      if (pcm16k != null) 'audioBase64': base64Encode(pcm16k),
    }, const Duration(seconds: 60));
  }

  Future<List<int>> synthesizeVoice(String text) async {
    _requireVoice();
    final payload = await requestMap(
      'mobile.voice.synthesize',
      <String, Object?>{'text': text},
      const Duration(seconds: 60),
    );
    final encoded = payload['audioBase64'];
    if (encoded is! String || encoded.isEmpty) {
      return const <int>[];
    }
    return base64Decode(encoded);
  }

  Future<void> markVoiceSpoken(
    String text, {
    int? id,
    bool failed = false,
    String? error,
  }) async {
    _requireVoice();
    await requestMap('mobile.voice.spoken', <String, Object?>{
      'text': text,
      'id': ?id,
      if (failed) 'failed': true,
      if (error != null && error.isNotEmpty) 'error': error,
    });
  }

  Future<void> sendVoiceAudio(List<int> pcm16k) async {
    _requireVoice();
    await requestMap('mobile.voice.audio', <String, Object?>{
      'audioBase64': base64Encode(pcm16k),
    });
  }

  Future<void> sendVoiceActivity(String phase) async {
    _requireVoice();
    await requestMap('mobile.voice.activity', <String, Object?>{
      'phase': phase,
    });
  }

  Future<MobileVoiceCredentialStatus> voiceCredentialStatus() async {
    _requireVoice();
    return MobileVoiceCredentialStatus.fromJson(
      await requestMap('mobile.voice.credentials.status'),
    );
  }

  Future<MobileVoiceCredentialStatus> saveVoiceCredentials({
    String? geminiToken,
    String? openaiToken,
  }) async {
    _requireVoice();
    return MobileVoiceCredentialStatus.fromJson(
      await requestMap('mobile.voice.credentials.save', <String, Object?>{
        'geminiToken': ?geminiToken,
        'openaiToken': ?openaiToken,
      }),
    );
  }

  Future<MobileVoiceCredentialStatus> clearVoiceCredentials({
    String? provider,
  }) async {
    _requireVoice();
    return MobileVoiceCredentialStatus.fromJson(
      await requestMap('mobile.voice.credentials.clear', <String, Object?>{
        'provider': ?provider,
      }),
    );
  }

  void _requireVoice() {
    if (!supportsVoiceHomeAgent) {
      throw UnsupportedError(
        'Update the paired runtime to use the voice home agent.',
      );
    }
  }
}
