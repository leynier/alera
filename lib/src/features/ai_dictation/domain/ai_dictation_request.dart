enum AiDictationRemoteEngine { codexSubscription, openAiCompatible }

class AiDictationRequest {
  const AiDictationRequest({
    required this.requestId,
    required this.audioPath,
    this.modelPath,
    this.language,
    this.initialPrompt,
    this.remoteEngine,
    this.providerBaseUrl,
    this.providerModel,
    this.timeout,
  });

  final String requestId;
  final String audioPath;
  final String? modelPath;
  final String? language;
  final String? initialPrompt;
  final AiDictationRemoteEngine? remoteEngine;
  final String? providerBaseUrl;
  final String? providerModel;
  final Duration? timeout;
}
