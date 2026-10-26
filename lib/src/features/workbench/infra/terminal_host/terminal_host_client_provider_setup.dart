part of 'terminal_host_client.dart';

extension _RemoteProviderSetupTransport on SocketTerminalHostClient {
  Future<Object?> _remoteProviderSetupRequest(
    _TerminalHostConnection connection,
    String type,
    Map<String, Object?> payload, {
    Duration? timeout,
  }) async {
    final sessionId = payload['sessionId'] as String;
    final (hostId, setup) = _remoteProviderSetupSessions[sessionId]!;
    if (!sessionId.startsWith(commandTerminalRemoteSetupSessionPrefix)) {
      throw StateError(
        'Remote provider setup requires an ephemeral setup session.',
      );
    }
    // Only the opaque selection crosses the link. The owner chooses its shell,
    // home directory, verified recipe and credential environment.
    final forwarded = <String, Object?>{
      ...payload,
      if (type == 'createOrAttach' || type == 'terminal.restart')
        'launch': <String, Object?>{'providerSetup': setup.toJson()},
    };
    if (type == 'createOrAttach' || type == 'terminal.restart') {
      forwarded.remove('workingDirectory');
    }
    final result = await _requestOnConnection(connection, 'hostLink.request', {
      'hostId': hostId,
      'type': 'hub.providerSetup',
      'payload': {
        'type': type,
        'providerSetup': setup.toJson(),
        'payload': forwarded,
      },
    }, timeout: timeout);
    if ((type == 'detach' || type == 'terminate') &&
        _remoteProviderSetupSessions[sessionId]?.$1 == hostId) {
      _remoteProviderSetupSessions.remove(sessionId);
    }
    return result;
  }
}
