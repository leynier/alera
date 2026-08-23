part of 'terminal_host_client.dart';

Future<T> _guardHostFuture<T>(Future<T> future) {
  // Connection futures are shared by several awaiters and can fail before
  // every awaiter has attached its own error handler.
  unawaited(
    future.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    ),
  );
  return future;
}

Future<Object?> _sendTerminalHostRequestWithMutationRetry(
  SocketTerminalHostClient client,
  _TerminalHostConnection connection,
  String type,
  Map<String, Object?> payload, {
  Duration? timeout,
}) async {
  final requestTimeout = timeout ?? _terminalHostRequestTimeout;
  final elapsed = Stopwatch()..start();
  while (true) {
    if (client._disposed) {
      throw StateError('Terminal host client is disposed.');
    }
    final remaining = requestTimeout - elapsed.elapsed;
    if (remaining <= Duration.zero) {
      client._noteRequestTimedOut(connection);
      throw TerminalHostRequestTimeoutException(type, requestTimeout);
    }
    try {
      return await _sendTerminalHostRequest(
        client,
        connection,
        type,
        payload,
        timeout: remaining,
        reportedTimeout: requestTimeout,
      );
    } on _RuntimeMutationInProgressError {
      final delayRemaining = requestTimeout - elapsed.elapsed;
      final delay = delayRemaining < _runtimeMutationRetryDelay
          ? delayRemaining
          : _runtimeMutationRetryDelay;
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
    }
  }
}

Future<Object?> _sendTerminalHostRequest(
  SocketTerminalHostClient client,
  _TerminalHostConnection connection,
  String type,
  Map<String, Object?> payload, {
  Duration? timeout,
  Duration? reportedTimeout,
}) {
  final id = client._nextRequestId++;
  final completer = Completer<Object?>();
  client._pending[id] = _PendingHostRequest(connection, completer);
  final requestTimeout = timeout ?? _terminalHostRequestTimeout;
  final response = completer.future.timeout(
    requestTimeout,
    onTimeout: () {
      final pending = client._pending[id];
      if (pending != null &&
          identical(pending.connection, connection) &&
          identical(pending.completer, completer)) {
        client._pending.remove(id);
      }
      // A timeout means one request was slow, not that the socket is dead.
      // Terminal and runtime traffic share this connection, so tearing it
      // down here would kill every live PTY and every runtime watcher over a
      // host that is merely saturated. Real death is reported by the socket
      // itself, and by the heartbeat for a peer that is alive but wedged.
      client._noteRequestTimedOut(connection);
      throw TerminalHostRequestTimeoutException(
        type,
        reportedTimeout ?? requestTimeout,
      );
    },
  );
  unawaited(response.catchError((Object _) => null));
  try {
    connection.write(<String, Object?>{
      'id': id,
      'type': type,
      'payload': payload,
    });
  } catch (error, stackTrace) {
    client._pending.remove(id);
    client._handleConnectionClosed(connection, error);
    if (!completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  }
  return response;
}

Object _terminalHostRequestError(Map<String, Object?> response) {
  final responseMessage = response['error'] as String?;
  final message = responseMessage ?? 'Terminal host error.';
  if (message == _runtimeMutationInProgressMessage) {
    return _RuntimeMutationInProgressError();
  }
  if (response['errorCode'] case final String code) {
    final rawDetails = response['errorDetails'];
    return TerminalHostConflictException(
      code: code,
      message: message,
      details: rawDetails is Map
          ? Map<String, Object?>.from(rawDetails)
          : const <String, Object?>{},
    );
  }
  return StateError(message);
}
