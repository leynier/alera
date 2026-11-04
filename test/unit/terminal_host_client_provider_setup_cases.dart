part of 'terminal_host_client_test.dart';

void _registerRemoteProviderSetupTests() {
  test('remote provider setup routes opaque selection, output, input and teardown to its owner', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-remote-setup-',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final server = await _TerminalHostTestServer.start();
    addTearDown(server.dispose);
    final client = SocketTerminalHostClient(
      launcher: _FakeTerminalHostLauncher(
        server: server,
        extraRuntimeCapabilities: const ['agentChatRemoteProviderSetupV1'],
      ),
      applicationSupportDirectory: () async => tempDir,
    );
    addTearDown(client.dispose);
    const sessionId = '${commandTerminalRemoteSetupSessionPrefix}session';
    const setup = CommandTerminalProviderSetup(
      providerInstanceId: 'work',
      action: 'signIn',
    );
    final events = <TerminalHostEvent>[];
    final subscription = client.eventsForSession(sessionId).listen(events.add);
    addTearDown(subscription.cancel);
    final launch = GhosttyTerminalShellLaunch(
      label: 'desktop shell',
      shell: '/desktop/shell',
      arguments: const ['ignored'],
      environment: const {'DESKTOP_TOKEN': 'desktop-secret'},
    );
    final attached = await client.providerSetupTerminal(
      sessionId: sessionId,
      workspaceId: commandTerminalWorkspaceId,
      tabId: 'session',
      workingDirectory: '/desktop/home',
      launch: launch,
      cols: 80,
      rows: 24,
      providerSetup: setup,
      hostId: 'owner',
    );
    expect(attached.sessionId, sessionId);
    final first = server.payloadFor('hostLink.request');
    expect(first['hostId'], 'owner');
    expect(first['type'], 'hub.providerSetup');
    final envelope = first['payload'] as Map;
    expect(envelope['providerSetup'], setup.toJson());
    expect((envelope['payload'] as Map)['launch'], {
      'providerSetup': setup.toJson(),
    });
    expect(jsonEncode(first), isNot(contains('desktop-secret')));
    expect(jsonEncode(first), isNot(contains('/desktop/shell')));
    expect(jsonEncode(first), isNot(contains('/desktop/home')));
    for (final hostId in ['another', 'owner']) {
      server.send({
        'event': 'hostLinkEvent',
        'payload': {
          'hostId': hostId,
          'event': 'output',
          'payload': {
            'sessionId': sessionId,
            'dataBase64': encodeTerminalHostBytes([65]),
          },
        },
      });
    }
    await client.write(sessionId: sessionId, bytes: [66]);
    await client.resize(sessionId: sessionId, cols: 100, rows: 30);
    expect(events.whereType<TerminalHostOutputEvent>().single.data, [65]);
    await client.providerSetupTerminal(
      sessionId: sessionId,
      workspaceId: commandTerminalWorkspaceId,
      tabId: 'session',
      workingDirectory: '/desktop/home',
      launch: launch,
      cols: 100,
      rows: 30,
      providerSetup: setup,
      hostId: 'owner',
      restart: true,
    );
    await client.terminate(sessionId);
    final operations = server
        .payloadsFor('hostLink.request')
        .map((request) => (request['payload'] as Map)['type'])
        .toList();
    expect(operations, [
      'createOrAttach',
      'write',
      'resize',
      'terminal.restart',
      'terminate',
    ]);
    expect(server.requestTypes, isNot(contains('write')));
    expect(server.requestTypes, isNot(contains('terminate')));
    client.releaseSession(sessionId);
  });

  test('remote provider setup refuses a host without the negotiated remote setup capability', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-remote-setup-',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final server = await _TerminalHostTestServer.start();
    addTearDown(server.dispose);
    final client = SocketTerminalHostClient(
      launcher: _FakeTerminalHostLauncher(server: server),
      applicationSupportDirectory: () async => tempDir,
    );
    addTearDown(client.dispose);
    await expectLater(
      client.providerSetupTerminal(
        sessionId: '${commandTerminalRemoteSetupSessionPrefix}session',
        workspaceId: commandTerminalWorkspaceId,
        tabId: 'tab',
        workingDirectory: '/desktop/home',
        launch: _launch(),
        cols: 80,
        rows: 24,
        providerSetup: const CommandTerminalProviderSetup(
          providerInstanceId: 'work',
          action: 'install',
        ),
        hostId: 'owner',
      ),
      throwsUnsupportedError,
    );
    expect(server.requestTypes, isNot(contains('hostLink.request')));
  });
}
