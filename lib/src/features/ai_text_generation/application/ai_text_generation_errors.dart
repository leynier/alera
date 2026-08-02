class AiTextGenerationException implements Exception {
  const AiTextGenerationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiTextGenerationCanceledException extends AiTextGenerationException {
  const AiTextGenerationCanceledException() : super('Generation canceled.');
}
