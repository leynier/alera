part of 'terminal_host_client_test.dart';

void _registerTerminalHostClientRuntimeMutationTests() {
  test(
    'status.get updates crash reports with the connected host version',
    () async {
      CrashReporting.resetForTesting();
      addTearDown(CrashReporting.resetForTesting);
      CrashReporting.configureAppVersion(version: '0.64.0', build: '112');
      CrashReporting.setEnabled(true);
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-host-status-',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final server = await _TerminalHostTestServer.start();
      addTearDown(server.dispose);
      await _writeControlFile(
        tempDir: tempDir,
        port: server.port,
        token: server.token,
      );
      final client = SocketTerminalHostClient(
        launcher: _NoopTerminalHostLauncher(),
        applicationSupportDirectory: () async => tempDir,
      );
      addTearDown(client.dispose);

      final status = await client.probeRuntimeStatus();
      final event = CrashReporting.filterEvent(SentryEvent());

      expect(status, containsPair('runtimeHostVersion', '1.7.0'));
      expect(event!.tags, containsPair('runtime_version', '1.7.0'));
      expect(event.tags, containsPair('runtime_build', 'abc1234'));
      expect(event.tags, containsPair('runtime_protocol', '4'));
    },
  );

  test('retries a request blocked by a concurrent runtime mutation', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-runtime-mutation-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final server = await _TerminalHostTestServer.start(
      runtimeMutationBusyForType: 'tab.upsert',
      runtimeMutationBusyResponses: 1,
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

    await client.runtimeRequest('tab.upsert', <String, Object?>{'id': 'tab-1'});

    expect(server.requestTypes, <String>['hello', 'tab.upsert', 'tab.upsert']);
  });

  test('bounds runtime mutation retries by the request timeout', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-runtime-mutation-timeout-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final server = await _TerminalHostTestServer.start(
      runtimeMutationBusyForType: 'tab.upsert',
      runtimeMutationBusyResponses: 100,
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
    const timeout = Duration(milliseconds: 70);

    await expectLater(
      client.runtimeRequest('tab.upsert', const <String, Object?>{
        'id': 'tab-1',
      }, timeout),
      throwsA(
        isA<TerminalHostRequestTimeoutException>().having(
          (error) => error.duration,
          'duration',
          timeout,
        ),
      ),
    );

    expect(server.requestTypes.where((type) => type == 'tab.upsert').length, 2);
  });
}
