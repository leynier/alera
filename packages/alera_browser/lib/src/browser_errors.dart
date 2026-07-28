/// Base exception raised by the Alera browser boundary.
sealed class AleraBrowserException implements Exception {
  const AleraBrowserException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'AleraBrowserException($code): $message';
}

/// The requested operation is not truthfully supported by the current engine.
final class AleraBrowserUnsupportedError extends AleraBrowserException {
  const AleraBrowserUnsupportedError(super.code, super.message);
}

/// The caller supplied an invalid profile, page, cookie, or action.
final class AleraBrowserStateError extends AleraBrowserException {
  const AleraBrowserStateError(super.code, super.message);
}

/// A native browser operation failed after it had been accepted.
final class AleraBrowserNativeError extends AleraBrowserException {
  const AleraBrowserNativeError(super.code, super.message);
}
