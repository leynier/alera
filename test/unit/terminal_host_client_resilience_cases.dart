part of 'terminal_host_client_test.dart';

void _registerTerminalHostClientResilienceTests() {
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
    'request timeout invalidates the connection before reconnecting',
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

      await client.detach('session-1');
      expect(server.requestTypes, <String>[
        'hello',
        'project.list',
        'hello',
        'detach',
      ]);
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

      await expectLater(client.detach('session-1'), throwsA(isA<StateError>()));

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
