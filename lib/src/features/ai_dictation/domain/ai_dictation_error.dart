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

class const AiDictationException(
  final AiDictationErrorKind kind,
  final String message, {
  final Object? cause,
}) implements Exception {
  @override
  String toString() => message;
}
