part of 'terminal_host_client_test.dart';

Future<SocketTerminalHostClient> _connectedClient(
  _TerminalHostTestServer server, {
  Duration heartbeatInterval = const Duration(seconds: 15),
  Duration heartbeatTimeout = const Duration(seconds: 5),
}) async {
  final tempDir = await Directory.systemTemp.createTemp('alera-host-timeout-');
  addTearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });
  await _writeControlFile(
    tempDir: tempDir,
    port: server.port,
    token: 'existing-token',
  );
  final client = SocketTerminalHostClient(
    launcher: _NoopTerminalHostLauncher(),
    applicationSupportDirectory: () async => tempDir,
    heartbeatInterval: heartbeatInterval,
    heartbeatTimeout: heartbeatTimeout,
  );
  addTearDown(client.dispose);
  return client;
}

void _registerTerminalHostClientTimeoutTests() {
  test('a sibling request still completes while another times out', () async {
    final server = await _TerminalHostTestServer.start(
      beforeResponse: (type) async {
        if (type == 'slow.request') {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      },
    );
    addTearDown(server.dispose);
    final client = await _connectedClient(server);

    final slow = client.runtimeRequest(
      'slow.request',
      const <String, Object?>{},
      const Duration(milliseconds: 50),
    );
    final fast = client.runtimeRequest('status.get');

    await expectLater(
      slow,
      throwsA(isA<TerminalHostRequestTimeoutException>()),
    );
    await expectLater(fast, completes);
  });

  test('the connection survives fewer failures than the probe limit', () async {
    final server = await _TerminalHostTestServer.start(
      beforeResponse: (type) async {
        if (type == 'slow.request' || type == 'status.get') {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      },
    );
    addTearDown(server.dispose);
    final client = await _connectedClient(
      server,
      heartbeatInterval: const Duration(milliseconds: 30),
      heartbeatTimeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      client.runtimeRequest(
        'slow.request',
        const <String, Object?>{},
        const Duration(milliseconds: 20),
      ),
      throwsA(isA<TerminalHostRequestTimeoutException>()),
    );
    // Two probe intervals: below the three-failure limit, so no teardown.
    await Future<void>.delayed(const Duration(milliseconds: 75));

    expect(server.acceptedConnections, 1);
  });

  test('a wedged host is torn down after the probe limit', () async {
    // Sockets cannot report a peer that is alive but stuck, so this is the
    // one case the heartbeat exists for.
    final server = await _TerminalHostTestServer.start(
      beforeResponse: (type) async {
        if (type != 'hello') {
          await Future<void>.delayed(const Duration(seconds: 5));
        }
      },
    );
    addTearDown(server.dispose);
    final client = await _connectedClient(
      server,
      heartbeatInterval: const Duration(milliseconds: 20),
      heartbeatTimeout: const Duration(milliseconds: 15),
    );

    await expectLater(
      client.runtimeRequest(
        'slow.request',
        const <String, Object?>{},
        const Duration(milliseconds: 20),
      ),
      throwsA(isA<TerminalHostRequestTimeoutException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));

    // The dead connection was dropped, so the next request reconnects.
    await expectLater(
      client.runtimeRequest(
        'status.get',
        const <String, Object?>{},
        const Duration(milliseconds: 50),
      ),
      throwsA(anything),
    );
    expect(server.acceptedConnections, greaterThan(1));
  });
}
