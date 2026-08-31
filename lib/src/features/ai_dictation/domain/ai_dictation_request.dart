enum AiDictationRemoteEngine { codexSubscription, openAiCompatible }

class const AiDictationRequest({
  required final String requestId,
  required final String audioPath,
  final String? modelPath,
  final String? language,
  final String? initialPrompt,
  final AiDictationRemoteEngine? remoteEngine,
  final String? providerBaseUrl,
  final String? providerModel,
  final Duration? timeout,
});
