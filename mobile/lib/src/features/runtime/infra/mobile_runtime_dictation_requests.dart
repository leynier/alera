part of 'mobile_runtime_client.dart';

mixin MobileRuntimeDictationRequests {
  bool get supportsAiDictation;
  bool get supportsAiDictationModels;

  Future<Map<String, Object?>> requestMap(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]);

  Future<Map<String, Object?>> transcribeMobileAudio({
    required String requestId,
    required List<int> audio,
    required String engine,
    required String modelId,
    String? language,
    String? initialPrompt,
  }) async {
    if (!supportsAiDictationModels) {
      throw UnsupportedError(
        'Update the paired runtime to select remote Dictation models.',
      );
    }
    final timeout = _mobileDictationTimeout(
      audioBytes: audio.length,
      modelId: modelId,
    );
    try {
      return await requestMap(
        'mobile.aiDictation.transcribe',
        <String, Object?>{
          'requestId': requestId,
          'audioBase64': base64Encode(audio),
          'engine': engine,
          'modelId': modelId,
          'language': language,
          'initialPrompt': initialPrompt,
        },
        timeout,
      );
    } on TimeoutException {
      try {
        await requestMap('mobile.aiDictation.cancel', <String, Object?>{
          'requestId': requestId,
        }, const Duration(seconds: 5));
      } on Object {
        // The original timeout remains the useful error for the caller.
      }
      rethrow;
    }
  }

  Future<void> cancelMobileAudioTranscription(String requestId) async {
    if (!supportsAiDictation) return;
    await requestMap('mobile.aiDictation.cancel', <String, Object?>{
      'requestId': requestId,
    });
  }
}

Duration _mobileDictationTimeout({
  required int audioBytes,
  required String modelId,
}) {
  final audioSeconds = (audioBytes / 32000).ceil();
  final modelAllowance = switch (modelId) {
    'whisper-large-v3-turbo-q5-0' => 180,
    'whisper-small' => 120,
    _ => 60,
  };
  return Duration(
    seconds: (60 + audioSeconds * 4 + modelAllowance).clamp(120, 900),
  );
}
