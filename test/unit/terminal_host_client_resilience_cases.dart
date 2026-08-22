part of 'terminal_host_client_test.dart';

Future<TerminalHostOutputResyncRequiredEvent> _sendOutputResyncEvent(
  SocketTerminalHostClient client,
  _TerminalHostTestServer server,
) {
  final event = client.events
      .where((event) => event is TerminalHostOutputResyncRequiredEvent)
      .cast<TerminalHostOutputResyncRequiredEvent>()
      .first;
  server.send(<String, Object?>{
    'event': 'outputResyncRequired',
    'payload': <String, Object?>{'sessionId': 'session-1'},
  });
  return event;
}

void _registerTerminalHostClientResilienceTests() {
  test('pulse state distinguishes an unavailable status from disarmed', () {
    final state = TerminalPulseState.fromJson(<String, Object?>{
      'configuration': const TerminalPulseConfiguration().toJson(),
      'error': 'status unavailable',
    });

    expect(state.armed, isFalse);
    expect(state.statusKnown, isFalse);
    expect(state.error, 'status unavailable');
  });

  test('write-side host closure reaches the caller as a typed error', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-write-close-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final server = await _TerminalHostTestServer.start(closeForType: 'write');
    addTearDown(server.dispose);
    await _writeControlFile(
      tempDir: tempDir,
      port: server.port,
      token: 'existing-token',
    );
    final client = SocketTerminalHostClient(
      launcher: _NoopTerminalHostLauncher(),
      applicationSupportDirectory: () async => tempDir,
    );
    addTearDown(client.dispose);

    await expectLater(
      client.write(sessionId: 'session-1', bytes: const <int>[1]),
      throwsA(isA<TerminalHostConnectionClosedException>()),
    );
  });

  test('socket closure notifies every attached session immediately', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-session-close-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final server = await _TerminalHostTestServer.start(closeForType: 'write');
    addTearDown(server.dispose);
    await _writeControlFile(
      tempDir: tempDir,
      port: server.port,
      token: 'existing-token',
    );
    final client = SocketTerminalHostClient(
      launcher: _NoopTerminalHostLauncher(),
      applicationSupportDirectory: () async => tempDir,
    );
    addTearDown(client.dispose);
    final sessionError = client
        .eventsForSession('session-1')
        .where((event) => event is TerminalHostErrorEvent)
        .cast<TerminalHostErrorEvent>()
        .first;

    await expectLater(
      client.write(sessionId: 'session-1', bytes: const <int>[1]),
      throwsA(isA<TerminalHostConnectionClosedException>()),
    );

    expect(
      (await sessionError).error.toString(),
      contains('connection closed'),
    );
  });

  test(
    'clean socket closure reports a stable error without a null reason',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-host-client-clean-close-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final server = await _TerminalHostTestServer.start();
      addTearDown(server.dispose);
      await _writeControlFile(
        tempDir: tempDir,
        port: server.port,
        token: 'existing-token',
      );
      final client = SocketTerminalHostClient(
        launcher: _NoopTerminalHostLauncher(),
        applicationSupportDirectory: () async => tempDir,
      );
      addTearDown(client.dispose);
      final sessionError = client
          .eventsForSession('session-1')
          .where((event) => event is TerminalHostErrorEvent)
          .cast<TerminalHostErrorEvent>()
          .first;

      await client.write(sessionId: 'session-1', bytes: const <int>[1]);
      server.closeClient();

      expect(
        (await sessionError).error,
        isA<TerminalHostConnectionClosedException>().having(
          (error) => error.toString(),
          'message',
          'Terminal host connection closed.',
        ),
      );
    },
  );

  test('pending RPC fails with a typed error when the socket closes', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-pending-stack-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final releaseWrite = Completer<void>();
    final server = await _TerminalHostTestServer.start(
      beforeResponse: (type) async {
        if (type == 'write') {
          await releaseWrite.future;
        }
      },
    );
    addTearDown(server.dispose);
    await _writeControlFile(
      tempDir: tempDir,
      port: server.port,
      token: 'existing-token',
    );
    final client = SocketTerminalHostClient(
      launcher: _NoopTerminalHostLauncher(),
      applicationSupportDirectory: () async => tempDir,
    );
    addTearDown(client.dispose);

    final request = client.write(sessionId: 'session-1', bytes: const <int>[1]);
    await _waitForServerRequestCount(server, 2);
    server.closeClient();
    releaseWrite.complete();

    await expectLater(
      request,
      throwsA(isA<TerminalHostConnectionClosedException>()),
    );
  });

  test('waits for authenticated hello before sending requests', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-authentication-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final releaseHello = Completer<void>();
    final server = await _TerminalHostTestServer.start(
      beforeResponse: (type) async {
        if (type == 'hello') {
          await releaseHello.future;
        }
      },
    );
    addTearDown(server.dispose);
    await _writeControlFile(
      tempDir: tempDir,
      port: server.port,
      token: 'existing-token',
    );
    final client = SocketTerminalHostClient(
      launcher: _NoopTerminalHostLauncher(),
      applicationSupportDirectory: () async => tempDir,
    );
    addTearDown(client.dispose);

    final request = client.runtimeRequest('project.list');
    await _waitForServerRequestCount(server, 1);
    expect(server.requestTypes, <String>['hello']);

    releaseHello.complete();
    await request;
    expect(server.requestTypes, <String>['hello', 'project.list']);
  });

  test(
    'request timeout fails only that request, not the shared connection',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-host-client-request-timeout-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final releaseRequest = Completer<void>();
      final server = await _TerminalHostTestServer.start(
        beforeResponse: (type) async {
          if (type == 'project.list') {
            await releaseRequest.future;
          }
        },
      );
      addTearDown(server.dispose);
      await _writeControlFile(
        tempDir: tempDir,
        port: server.port,
        token: 'existing-token',
      );
      final client = SocketTerminalHostClient(
        launcher: _NoopTerminalHostLauncher(),
        applicationSupportDirectory: () async => tempDir,
      );
      addTearDown(client.dispose);

      await expectLater(
        client.runtimeRequest(
          'project.list',
          const <String, Object?>{},
          const Duration(milliseconds: 20),
        ),
        throwsA(
          isA<TerminalHostRequestTimeoutException>()
              .having(
                (error) => error.requestType,
                'requestType',
                'project.list',
              )
              .having(
                (error) => error.duration,
                'duration',
                const Duration(milliseconds: 20),
              ),
        ),
      );

      // Terminal output and every runtime watcher ride this one socket, so a
      // slow request must not cost a reconnect: only one `hello` is sent.
      releaseRequest.complete();
      await client.detach('session-1');
      expect(server.requestTypes, <String>['hello', 'project.list', 'detach']);
    },
  );

  test(
    'retries terminal connection after an authentication attempt fails',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-host-client-terminal-auth-retry-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final launcher = _NoopTerminalHostLauncher();
      final client = SocketTerminalHostClient(
        launcher: launcher,
        applicationSupportDirectory: () async => tempDir,
        startupTimeout: Duration.zero,
      );
      addTearDown(client.dispose);

      await expectLater(
        client.detach('session-1'),
        throwsA(isA<TerminalHostStartupException>()),
      );

      final server = await _TerminalHostTestServer.start();
      addTearDown(server.dispose);
      await _writeControlFile(
        tempDir: tempDir,
        port: server.port,
        token: 'retry-token',
      );

      await client.detach('session-1');

      expect(launcher.starts, 1);
      expect(server.requestTypes, <String>['hello', 'detach']);
    },
  );

  test('forwards agentPresenceChanged on runtimeEvents', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-agent-presence-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final server = await _TerminalHostTestServer.start();
    addTearDown(server.dispose);
    final client = SocketTerminalHostClient(
      launcher: _FakeTerminalHostLauncher(server: server),
      applicationSupportDirectory: () async => tempDir,
    );
    addTearDown(client.dispose);

    await client.ensureStarted(config: TerminalHostConfig.defaults);
    final runtimeEvent = client.runtimeEvents.first;

    server.send(<String, Object?>{
      'event': 'agentPresenceChanged',
      'payload': <String, Object?>{},
    });

    final event = await runtimeEvent;
    expect(event.name, 'agentPresenceChanged');
    expect(event.payload, <String, Object?>{});
  });
}

Future<void> _waitForServerRequestCount(
  _TerminalHostTestServer server,
  int expected,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (server.requests.length < expected &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(server.requests.length, greaterThanOrEqualTo(expected));
}
