part of 'terminal_host_client.dart';

extension _TerminalHostBufferGuards on SocketTerminalHostClient {
  /// Locks the guard's editors and acknowledges with what still blocks it.
  /// A guard asking to `save` or `discard` settles the dirty editors first,
  /// when this client's handler can.
  void _lockCheckoutBuffers(
    _TerminalHostConnection connection,
    Map<String, Object?> payload, {
    String? resolution,
  }) {
    final id = payload['guardId'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('A buffer guard ID is required.');
    }
    unawaited(
      _checkoutBufferBlockers(connection, id, payload, resolution)
          .then(
            (blockers) => _requestOnConnection(
              connection,
              'workspace.bufferGuard.ack',
              {'guardId': id, 'blockers': blockers},
            ),
          )
          .catchError((Object error) {
            AppLogger.recordError(
              error,
              .current,
              context: 'WorkspaceBufferGuard',
            );
            return null;
          }),
    );
  }

  Future<List<Map<String, Object?>>> _checkoutBufferBlockers(
    _TerminalHostConnection connection,
    String id,
    Map<String, Object?> payload,
    String? resolution,
  ) async {
    try {
      final scope = asTerminalHostMap(payload['scope'], 'buffer guard scope');
      final handler = _bufferGuardHandler;
      if (handler == null) {
        throw StateError('This client cannot verify editor buffers.');
      }
      final tabIds = (scope['tabIds'] as List).cast<String>().toSet();
      final workspacePaths = (scope['workspacePaths'] as List)
          .cast<String>()
          .toSet();
      if (handler is RuntimeBufferGuardResolver &&
          (resolution == 'save' || resolution == 'discard')) {
        _resolvingBufferGuards.add(id);
        final blockers = await handler.resolveAndLock(
          guardId: id,
          tabIds: tabIds,
          workspacePaths: workspacePaths,
          discard: resolution == 'discard',
        );
        if (!_resolvingBufferGuards.remove(id)) {
          // The runtime released the guard while the editors were saving.
          handler.release(id);
          return blockers;
        }
        _heldBufferGuards.putIfAbsent(id, () => {}).add(connection);
        return blockers;
      }
      final blockers = handler.lock(
        guardId: id,
        tabIds: tabIds,
        workspacePaths: workspacePaths,
      );
      _heldBufferGuards.putIfAbsent(id, () => {}).add(connection);
      return blockers;
    } catch (error) {
      return [
        {
          'tabId': '',
          'path': '',
          'reason': 'Could not verify editor buffers: $error',
        },
      ];
    }
  }

  void _releaseCheckoutBuffers(String id, {bool retired = false}) {
    _resolvingBufferGuards.remove(id);
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
