import "dart:async";

/// Cancellation signal shared by update download, verification, and staging.
///
/// Cancellation is cooperative for asynchronous work. ZIP extraction uses the
/// signal to terminate its worker isolate, so a large archive cannot continue
/// consuming the UI isolate after the update owner has been disposed.
class UpdateCancellationToken {
  /// Creates a token in the active state.
  UpdateCancellationToken();

  final Completer<void> _cancelled = Completer<void>();

  /// Whether cancellation has been requested.
  bool get isCancelled => _cancelled.isCompleted;

  /// Completes when cancellation is requested.
  Future<void> get whenCancelled => _cancelled.future;

  /// Requests cancellation. Repeated calls are harmless.
  void cancel() {
    if (!isCancelled) {
      _cancelled.complete();
    }
  }

  /// Throws when cancellation has already been requested.
  void throwIfCancelled() {
    if (isCancelled) {
      throw const UpdateCancelledException();
    }
  }
}

/// Raised when update staging is cancelled before it can complete.
class UpdateCancelledException implements Exception {
  /// Creates a cancellation error.
  const UpdateCancelledException();

  @override
  String toString() => "The update staging operation was cancelled.";
}
