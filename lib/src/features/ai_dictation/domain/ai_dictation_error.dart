enum AiDictationErrorKind {
  disabled,
  permissionDenied,
  modelUnavailable,
  targetUnavailable,
  audio,
  invalidRequest,
  cancelled,
  transcription,
}

class AiDictationException implements Exception {
  const AiDictationException(this.kind, this.message, {this.cause});

  final AiDictationErrorKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
