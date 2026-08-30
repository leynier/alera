class const AiAssistException(final String message) implements Exception {
  @override
  String toString() => message;
}

class const AiAssistCanceledException() extends AiAssistException {
  this : super('Generation canceled.');
}
