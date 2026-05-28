part of 'terminal_host_server_test.dart';

void _registerTerminalHostServerConfigurationTests() {
  test('applies configure requests to lifecycle and output buffers', () async {
    final harness = await _TerminalHostServerHarness.start(
      config: const TerminalHostConfig(scrollbackBytes: 64),
    );
    addTearDown(() async {
      await harness.dispose();
      if (await harness.tempDir.exists()) {
        await harness.tempDir.delete(recursive: true);
      }
    });
    final client = await harness.connect();
    addTearDown(client.dispose);
    await client.hello(harness.token);

    final configured = await client.request(
      'configure',
      const TerminalHostConfig(
        emptyShutdownDelaySeconds: 1,
        detachedSessionShutdownDelaySeconds: 2,
        scrollbackBytes: 8,
      ).toJson(),
    );
    expect(configured['ok'], isTrue);
    final invalidConfig = await client.request('configure', <String, Object?>{
      'emptyShutdownDelaySeconds': 1,
      'detachedSessionShutdownDelaySeconds': 2,
      'scrollbackBytes': 0,
    });
    expect(invalidConfig['ok'], isFalse);
    expect(invalidConfig['error'], contains('scrollbackBytes'));

    final created = await client.request('createOrAttach', <String, Object?>{
      'sessionId': 'trimmed-output',
      'workspaceId': 'workspace-1',
      'tabId': 'tab-1',
      'workingDirectory': Directory.current.path,
      'launch': const TerminalHostLaunch(
        label: 'trim output shell',
        shell: '/bin/sh',
        arguments: <String>['-c', 'printf abcdefghijklmno'],
        environment: <String, String>{},
      ).toJson(),
    });
    expect(created.payload['created'], isTrue);
    await client.event('exit', sessionId: 'trimmed-output');

    final attached = await client.request('createOrAttach', <String, Object?>{
      'sessionId': 'trimmed-output',
      'workspaceId': 'workspace-1',
      'tabId': 'tab-1',
      'workingDirectory': Directory.current.path,
      'launch': const TerminalHostLaunch(
        label: 'noop',
        shell: '/bin/sh',
        arguments: <String>['-c', 'exit 0'],
        environment: <String, String>{},
      ).toJson(),
    });
    expect(attached.payload['created'], isFalse);
    expect(
      utf8.decode(decodeTerminalHostBytes(attached.payload['snapshotBase64'])),
      'hijklmno',
    );

    final shrunk = await client.request(
      'configure',
      const TerminalHostConfig(
        emptyShutdownDelaySeconds: 1,
        detachedSessionShutdownDelaySeconds: 2,
        scrollbackBytes: 4,
      ).toJson(),
    );
    expect(shrunk['ok'], isTrue);
    final reattached = await client.request('createOrAttach', <String, Object?>{
      'sessionId': 'trimmed-output',
      'workspaceId': 'workspace-1',
      'tabId': 'tab-1',
      'workingDirectory': Directory.current.path,
      'launch': const TerminalHostLaunch(
        label: 'noop',
        shell: '/bin/sh',
        arguments: <String>['-c', 'exit 0'],
        environment: <String, String>{},
      ).toJson(),
    });
    expect(
      utf8.decode(
        decodeTerminalHostBytes(reattached.payload['snapshotBase64']),
      ),
      'lmno',
    );
  });

  test('stops an empty detached host after the configured delay', () async {
    final harness = await _TerminalHostServerHarness.start(
      config: const TerminalHostConfig(
        emptyShutdownDelaySeconds: 1,
        detachedSessionShutdownDelaySeconds: 10,
      ),
    );
    addTearDown(() async {
      await harness.dispose();
      if (await harness.tempDir.exists()) {
        await harness.tempDir.delete(recursive: true);
      }
    });

    await harness.waitForStop();

    expect(await harness.controlFile.exists(), isFalse);
  });

  test(
    'terminates detached running sessions after the configured delay',
    () async {
      final harness = await _TerminalHostServerHarness.start(
        config: const TerminalHostConfig(
          emptyShutdownDelaySeconds: 10,
          detachedSessionShutdownDelaySeconds: 1,
        ),
      );
      addTearDown(() async {
        await harness.dispose();
        if (await harness.tempDir.exists()) {
          await harness.tempDir.delete(recursive: true);
        }
      });
      final client = await harness.connect();
      await client.hello(harness.token);

      final created = await client.request('createOrAttach', <String, Object?>{
        'sessionId': 'detached-running',
        'workspaceId': 'workspace-1',
        'tabId': 'tab-1',
        'workingDirectory': Directory.current.path,
        'launch': const TerminalHostLaunch(
          label: 'detached shell',
          shell: '/bin/sh',
          arguments: <String>['-c', 'printf still-running; sleep 30'],
          environment: <String, String>{},
        ).toJson(),
      });
      expect(created.payload['created'], isTrue);
      expect(
        await client.outputContaining('detached-running', 'still-running'),
        contains('still-running'),
      );

      await client.dispose();
      await harness.waitForStop();

      expect(await harness.controlFile.exists(), isFalse);
      final history = await harness.readHistory('detached-running');
      expect(history, isNotNull);
      expect(history!.running, isFalse);
      expect(history.endedAt, isNotNull);
      expect(utf8.decode(history.buffer), contains('still-running'));
    },
  );

  test(
    'keeps restored snapshots within the configured output buffer',
    () async {
      final harness = await _TerminalHostServerHarness.start(
        config: const TerminalHostConfig(scrollbackBytes: 1024 * 1024),
      );
      _TerminalHostServerHarness? restoredHarness;
      addTearDown(() async {
        await restoredHarness?.dispose();
        await harness.dispose();
        if (await harness.tempDir.exists()) {
          await harness.tempDir.delete(recursive: true);
        }
      });
      final client = await harness.connect();
      addTearDown(client.dispose);
      await client.hello(harness.token);

      final created = await client.request('createOrAttach', <String, Object?>{
        'sessionId': 'large-output',
        'workspaceId': 'workspace-1',
        'tabId': 'tab-1',
        'workingDirectory': Directory.current.path,
        'launch': const TerminalHostLaunch(
          label: 'large output shell',
          shell: '/bin/sh',
          arguments: <String>['-c', r"head -c 1050000 /dev/zero | tr '\0' x"],
          environment: <String, String>{},
        ).toJson(),
      });
      expect(created.payload['created'], isTrue);
      final exit = await client.event('exit', sessionId: 'large-output');
      expect(exit.payload['exitCode'], 0);

      await harness.dispose();
      restoredHarness = await _TerminalHostServerHarness.start(
        tempDir: harness.tempDir,
        token: 'restored-token',
      );
      final restoredClient = await restoredHarness.connect();
      addTearDown(restoredClient.dispose);
      await restoredClient.hello(restoredHarness.token);
      final restored = await restoredClient.request(
        'createOrAttach',
        <String, Object?>{
          'sessionId': 'large-output',
          'workspaceId': 'workspace-1',
          'tabId': 'tab-1',
          'workingDirectory': Directory.current.path,
          'launch': const TerminalHostLaunch(
            label: 'shell',
            shell: '/bin/sh',
            arguments: <String>['-c', 'exit 0'],
            environment: <String, String>{},
          ).toJson(),
        },
      );
      expect(restored.payload['created'], isFalse);
      expect(
        decodeTerminalHostBytes(restored.payload['snapshotBase64']).length,
        1024 * 1024,
      );
    },
  );
}

extension on Map<String, Object?> {
  Map<String, Object?> get payload {
    return Map<String, Object?>.from(this['payload']! as Map);
  }
}
