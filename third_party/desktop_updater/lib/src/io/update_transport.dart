import "dart:io";

abstract interface class UpdateTransport {
  Future<void> download(
    Uri source,
    File destination, {
    void Function(int receivedBytes, int? totalBytes)? onProgress,
    Duration? timeout,
  });
}

/// Optional cancellation boundary for transports that own an active socket.
abstract interface class CancellableUpdateTransport implements UpdateTransport {
  /// Aborts the active transfer and releases its socket.
  Future<void> cancel();
}
