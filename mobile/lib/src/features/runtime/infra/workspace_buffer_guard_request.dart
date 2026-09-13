typedef WorkspaceOperationRequest = Future<Object?> Function(
  String type,
  Map<String, Object?> payload,
  Duration? timeout,
);

Future<Object?> requestWithWorkspaceBufferGuard({
  required WorkspaceOperationRequest request,
  required String workspaceId,
  required String operation,
  required Map<String, Object?> payload,
  required Duration timeout,
}) async {
  var status = _guardResponse(
    await request('workspace.bufferGuard.acquire', {
      'id': workspaceId,
      'operation': operation,
    }, const Duration(seconds: 15)),
  );
  final id = status['guardId'];
  if (id is! String || id.isEmpty) {
    throw const FormatException('The runtime did not return a buffer guard.');
  }
  final elapsed = Stopwatch()..start();
  try {
    while (status['ready'] != true) {
      final blockers = status['blockers'];
      if (blockers is! List) {
        throw const FormatException(
          'The runtime did not verify editor buffers.',
        );
      }
      if (blockers.isNotEmpty) {
        throw StateError(
          'Resolve editor buffers on the connected clients before continuing:\n${blockers.map((blocker) {
            final entry = _guardResponse(blocker);
            return '${entry['path']}: ${entry['reason']}';
          }).join('\n')}',
        );
      }
      if (status['disconnectedClients'] != 0) {
        throw StateError(
          'A client disconnected during buffer verification. Prepare the operation again.',
        );
      }
      if (elapsed.elapsed >= const Duration(seconds: 20)) {
        throw StateError(
          'Some connected editors did not respond. The workspace was preserved.',
        );
      }
      await Future.pause(const Duration(milliseconds: 100));
      status = _guardResponse(
        await request('workspace.bufferGuard.status', {
          'guardId': id,
        }, const Duration(seconds: 5)),
      );
    }
    return await request('workspace.$operation', {
      ...payload,
      'bufferGuardId': id,
    }, timeout);
  } finally {
    elapsed.stop();
    try {
      await request('workspace.bufferGuard.release', {
        'guardId': id,
      }, const Duration(seconds: 5));
    } on Object {
      // A running mutation owns the lock until it finishes, including when
      // this caller timed out. Pending preparations also expire on the host.
    }
  }
}

Map<String, Object?> _guardResponse(Object? value) {
  if (value is! Map) {
    throw const FormatException('Invalid buffer verification response.');
  }
  return Map<String, Object?>.from(value);
}
