class AiDictationResult {
  const AiDictationResult({
    required this.text,
    required this.providerId,
    required this.elapsed,
    required this.duration,
    this.detectedLanguage,
  });

  final String text;
  final String providerId;
  final Duration elapsed;
  final Duration duration;
  final String? detectedLanguage;
}
