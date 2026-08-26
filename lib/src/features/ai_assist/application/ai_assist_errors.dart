class AiAssistException implements Exception {
  const AiAssistException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiAssistCanceledException extends AiAssistException {
  const AiAssistCanceledException() : super('Generation canceled.');
}
