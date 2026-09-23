part of 'terminal_host_client.dart';

extension _TerminalHostBufferGuards on SocketTerminalHostClient {
  void _lockCheckoutBuffers(
    _TerminalHostConnection connection,
    Map<String, Object?> payload,
  ) {
    final id = payload['guardId'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('A buffer guard ID is required.');
    }
    List<Map<String, Object?>> blockers;
    try {
      final scope = asTerminalHostMap(payload['scope'], 'buffer guard scope');
      final handler = _bufferGuardHandler;
      if (handler == null) {
        throw StateError('This client cannot verify editor buffers.');
      }
      blockers = handler.lock(
        guardId: id,
        tabIds: (scope['tabIds'] as List).cast<String>().toSet(),
        workspacePaths: (scope['workspacePaths'] as List)
            .cast<String>()
            .toSet(),
      );
      _heldBufferGuards.putIfAbsent(id, () => {}).add(connection);
    } catch (error) {
      blockers = [
        {
          'tabId': '',
          'path': '',
          'reason': 'Could not verify editor buffers: $error',
        },
      ];
    }
    unawaited(
      _requestOnConnection(connection, 'workspace.bufferGuard.ack', {
        'guardId': id,
        'blockers': blockers,
      }).catchError((Object error) {
        AppLogger.recordError(error, .current, context: 'WorkspaceBufferGuard');
        return null;
      }),
    );
  }

  void _releaseCheckoutBuffers(String id, {bool retired = false}) {
    _heldBufferGuards.remove(id);
    _bufferGuardHandler?.release(id, retired: retired);
  }

  void _restoreCheckoutBufferGuards(
    _TerminalHostConnection connection,
    Map<String, Object?> payload,
  ) {
    final guards = payload['checkoutBufferGuards'];
    if (guards is! List) return;
    final active = <String>{};
    for (final value in guards) {
      final guard = asTerminalHostMap(value, 'buffer guard');
      final id = guard['guardId'];
      if (id is String) active.add(id);
      _lockCheckoutBuffers(connection, guard);
    }
    for (final entry in _heldBufferGuards.entries.toList()) {
      if (!active.contains(entry.key) &&
          entry.value.every((owner) => owner.isClosed)) {
        _releaseCheckoutBuffers(entry.key);
      }
    }
  }
}
