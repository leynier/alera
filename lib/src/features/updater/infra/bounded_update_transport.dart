import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Raised when a backend is disposed while an artifact is downloading.
class const UpdateDownloadCancelledException() implements Exception {
  @override
  String toString() => 'The update download was cancelled.';
}

/// Raised before an artifact can write more than its signed length to disk.
class const UpdateArtifactTooLargeException({
  required this.expectedBytes,
  required this.receivedBytes,
}) implements Exception {
  final int expectedBytes;
  final int receivedBytes;

  @override
  String toString() {
    return 'The update artifact exceeds its signed size of '
        '$expectedBytes bytes (received at least $receivedBytes).';
  }
}

/// Supplies the updater package with a bounded, abortable artifact response.
///
/// `desktop_updater` creates its HTTP transport through `http.Client()`. The
/// backend installs this client with `http.runWithClient`, retaining the
/// package's public verification, extraction, and staging path while closing
/// the underlying socket when a response stalls, exceeds its signed size, or
/// the owning service is disposed.
class BoundedUpdateTransport extends http.BaseClient {
  BoundedUpdateTransport({required this.maxBytes, required this.timeout}) {
    if (maxBytes < 0) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'must not be negative');
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
  }

  final int maxBytes;
  final Duration timeout;
  IOClient _delegate = IOClient();
  StreamSubscription<List<int>>? _activeSubscription;
  StreamController<List<int>>? _activeController;
  Object? _terminalError;
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) {
      throw StateError('The update transport has been closed.');
    }
    final terminalError = _terminalError;
    if (terminalError != null) {
      throw terminalError;
    }

    final delegate = _delegate;
    late final http.StreamedResponse response;
    try {
      response = await delegate.send(request).timeout(timeout);
    } catch (error, stackTrace) {
      final aborted = _terminalError;
      if (aborted != null) {
        Error.throwWithStackTrace(aborted, StackTrace.current);
      }
      _abort(error);
      Error.throwWithStackTrace(error, stackTrace);
    }
    final aborted = _terminalError;
    if (aborted != null) {
      Error.throwWithStackTrace(aborted, StackTrace.current);
    }

    final contentLength = response.contentLength;
    if (contentLength != null && contentLength > maxBytes) {
      final error = UpdateArtifactTooLargeException(
        expectedBytes: maxBytes,
        receivedBytes: contentLength,
      );
      _abort(error);
      throw error;
    }

    var receivedBytes = 0;
    var terminated = false;
    StreamSubscription<List<int>>? subscription;
    late StreamController<List<int>> controller;

    void fail(Object error, StackTrace stackTrace) {
      if (terminated || controller.isClosed) {
        return;
      }
      terminated = true;
      final terminalError = _terminalError ?? error;
      _abort(terminalError);
      controller.addError(terminalError, stackTrace);
      unawaited(controller.close());
      final currentSubscription = subscription;
      if (currentSubscription != null) {
        unawaited(_cancelSubscription(currentSubscription));
      }
    }

    controller = StreamController<List<int>>(
      sync: true,
      onListen: () {
        final terminalError = _terminalError;
        if (terminalError != null) {
          terminated = true;
          if (!controller.isClosed) {
            controller.addError(terminalError, StackTrace.current);
            unawaited(controller.close());
          }
          return;
        }
        subscription = response.stream
            .timeout(timeout)
            .listen(
              (chunk) {
                if (terminated) {
                  return;
                }
                receivedBytes += chunk.length;
                if (receivedBytes > maxBytes) {
                  fail(
                    UpdateArtifactTooLargeException(
                      expectedBytes: maxBytes,
                      receivedBytes: receivedBytes,
                    ),
                    StackTrace.current,
                  );
                  return;
                }
                controller.add(chunk);
              },
              onError: (Object error, StackTrace stackTrace) {
                fail(error, stackTrace);
              },
              onDone: () {
                final terminalError = _terminalError;
                if (terminalError != null) {
                  fail(terminalError, StackTrace.current);
                  return;
                }
                if (terminated) {
                  return;
                }
                terminated = true;
                unawaited(controller.close());
                _releaseDelegate(delegate);
              },
              cancelOnError: false,
            );
        _activeSubscription = subscription;
        final racedError = _terminalError;
        if (racedError != null) {
          terminated = true;
          if (!controller.isClosed) {
            controller.addError(racedError, StackTrace.current);
            unawaited(controller.close());
          }
          unawaited(_cancelSubscription(subscription!));
        }
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () async {
        final currentSubscription = subscription;
        if (currentSubscription != null) {
          await _cancelSubscription(currentSubscription);
        }
        if (identical(_activeSubscription, currentSubscription)) {
          _activeSubscription = null;
        }
        if (identical(_activeController, controller)) {
          _activeController = null;
        }
        _releaseDelegate(delegate);
      },
    );
    _activeController = controller;

    return http.StreamedResponse(
      controller.stream,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }

  /// Aborts an active response and prevents the package retry policy from
  /// reopening it after a cancellation, timeout, or size violation.
  Future<void> cancel() async {
    if (_closed) {
      return;
    }
    final error = _terminalError ?? const UpdateDownloadCancelledException();
    _abort(error);
    final controller = _activeController;
    if (controller != null && !controller.isClosed) {
      controller.addError(error, StackTrace.current);
      unawaited(controller.close());
    }
    final subscription = _activeSubscription;
    if (subscription != null) {
      await _cancelSubscription(subscription);
      if (identical(_activeSubscription, subscription)) {
        _activeSubscription = null;
      }
    }
  }

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    final error = _terminalError ?? const UpdateDownloadCancelledException();
    _abort(error);
    final controller = _activeController;
    if (controller != null && !controller.isClosed) {
      controller.addError(error, StackTrace.current);
      unawaited(controller.close());
    }
    final subscription = _activeSubscription;
    if (subscription != null) {
      unawaited(_cancelSubscription(subscription));
    }
  }

  void _abort(Object error) {
    _terminalError ??= error;
    _delegate.close();
  }

  void _releaseDelegate(IOClient delegate) {
    delegate.close();
    if (identical(_delegate, delegate) && !_closed && _terminalError == null) {
      _delegate = IOClient();
    }
  }

  Future<void> _cancelSubscription(
    StreamSubscription<List<int>> subscription,
  ) async {
    try {
      await subscription.cancel().timeout(const Duration(seconds: 1));
    } on Object {
      // Socket teardown is already requested by closing the delegate. A
      // broken stream cancellation must not keep the updater waiting.
    }
  }
}
