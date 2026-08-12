class AiDictationRequest {
  const AiDictationRequest({
    required this.requestId,
    required this.audioPath,
    required this.modelPath,
    this.language,
    this.initialPrompt,
    this.providerBaseUrl,
    this.providerModel,
    this.providerApiKey,
    this.timeout,
  });

  final String requestId;
  final String audioPath;
  final String modelPath;
  final String? language;
  final String? initialPrompt;
  final String? providerBaseUrl;
  final String? providerModel;
  final String? providerApiKey;
  final Duration? timeout;
}
