class AiDictationRequest {
  const AiDictationRequest({
    required this.requestId,
    required this.audioPath,
    required this.modelPath,
    this.language,
    this.initialPrompt,
  });

  final String requestId;
  final String audioPath;
  final String modelPath;
  final String? language;
  final String? initialPrompt;
}
