part of 'terminal_host_client.dart';

mixin _GuardedRuntimeHostClientSupport implements GuardedRuntimeHostClient {
  @override
  Future<Object?> guardedRuntimeRequest(
    String type,
    Map<String, Object?> payload, {
    required void Function(Map<String, Object?> status) validateStatus,
    Duration? timeout,
  }) => _guardedRuntimeRequest(
    this as SocketTerminalHostClient,
    type,
    payload,
    validateStatus: validateStatus,
    timeout: timeout,
  );
}

Future<Object?> _guardedRuntimeRequest(
  SocketTerminalHostClient client,
  String type,
  Map<String, Object?> payload, {
  required void Function(Map<String, Object?> status) validateStatus,
  Duration? timeout,
}) async {
  if (client._disposed) {
    throw StateError('Terminal host client is disposed.');
  }
  final connection = await client._connectRuntime(
    requireOrchestration: type.startsWith('orchestration.'),
  );
  final status = asTerminalHostMap(
    await client._requestOnConnection(
      connection,
      'status.get',
      const <String, Object?>{},
      timeout: timeout,
    ),
    'runtime status',
  );
  validateStatus(status);
  if (connection.isClosed) {
    throw const TerminalHostConnectionClosedException();
  }
  return client._requestOnConnection(
    connection,
    type,
    payload,
    timeout: timeout,
  );
}
