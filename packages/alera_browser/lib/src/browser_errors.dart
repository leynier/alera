/// Base exception raised by the Alera browser boundary.
sealed class const AleraBrowserException(
  final String code,
  final String message,
) implements Exception {
  @override
  String toString() => 'AleraBrowserException($code): $message';
}

/// The requested operation is not truthfully supported by the current engine.
final class const AleraBrowserUnsupportedError(super.code, super.message)
    extends AleraBrowserException;

/// The caller supplied an invalid profile, page, cookie, or action.
final class const AleraBrowserStateError(super.code, super.message)
    extends AleraBrowserException;

/// A native browser operation failed after it had been accepted.
final class const AleraBrowserNativeError(super.code, super.message)
    extends AleraBrowserException;
