part of 'terminal_host_client.dart';

Future<Object?> _sendTerminalHostRequest(
  SocketTerminalHostClient client,
  _TerminalHostConnection connection,
  String type,
  Map<String, Object?> payload, {
  Duration? timeout,
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
      final error = TerminalHostRequestTimeoutException(type, requestTimeout);
      client._handleConnectionClosed(connection, error);
      throw error;
    },
  );
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
