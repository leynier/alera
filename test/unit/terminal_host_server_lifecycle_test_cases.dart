part of 'terminal_host_server_test.dart';

void _registerTerminalHostServerLifecycleTests() {
  test(
    'authenticates clients, drives PTY sessions, and restores history',
    () async {
      final harness = await _TerminalHostServerHarness.start();
      _TerminalHostServerHarness? restoredHarness;
      addTearDown(() async {
        await restoredHarness?.dispose();
        await harness.dispose();
        if (await harness.tempDir.exists()) {
          await harness.tempDir.delete(recursive: true);
        }
      });

      final rejectedClient = await harness.connect();
      addTearDown(rejectedClient.dispose);
      final rejectedHello = await rejectedClient.hello('wrong-token');
      expect(rejectedHello['ok'], isFalse);

      final client = await harness.connect();
      addTearDown(client.dispose);
      final hello = await client.hello(harness.token);
      expect(hello['ok'], isTrue);

      final create = await client.request('createOrAttach', <String, Object?>{
        'sessionId': 'session-1',
        'workspaceId': 'workspace-1',
        'tabId': 'tab-1',
        'workingDirectory': Directory.current.path,
        'launch': const TerminalHostLaunch(
          label: 'shell',
          shell: '/bin/sh',
          arguments: <String>[
            '-c',
            r'printf ready; IFS= read -r line; printf "got:%s" "$line"; exit 7',
          ],
          environment: <String, String>{'TERM': 'xterm-256color'},
        ).toJson(),
        'cols': 80,
        'rows': 24,
      });
      expect(create['ok'], isTrue);
      expect(create.payload['created'], isTrue);
      expect(create.payload['running'], isTrue);

      final secondClient = await harness.connect();
      addTearDown(secondClient.dispose);
      await secondClient.hello(harness.token);
      final attached = await secondClient.request(
        'createOrAttach',
        <String, Object?>{
          'sessionId': 'session-1',
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
      expect(attached.payload['created'], isFalse);
      expect(attached.payload['running'], isTrue);
      await secondClient.request('detach', <String, Object?>{
        'sessionId': 'session-1',
      });

      expect(
        await client.outputContaining('session-1', 'ready'),
        contains('ready'),
      );
      await client.request('resize', <String, Object?>{
        'sessionId': 'session-1',
        'cols': 100,
        'rows': 30,
      });
      await client.request('write', <String, Object?>{
        'sessionId': 'session-1',
        'dataBase64': encodeTerminalHostBytes(utf8.encode('abc\r')),
      });

      final output = await client.outputContaining('session-1', 'got:abc');
      expect(output, contains('got:abc'));
      final exit = await client.event('exit', sessionId: 'session-1');
      expect(exit.payload['exitCode'], 7);

      await client.dispose();
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
          'sessionId': 'session-1',
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
      expect(restored.payload['running'], isFalse);
      expect(restored.payload['exitCode'], 7);
      expect(
        utf8.decode(
          decodeTerminalHostBytes(restored.payload['snapshotBase64']),
        ),
        contains('got:abc'),
      );

      await restoredClient.request('detach', <String, Object?>{
        'sessionId': 'session-1',
      });
      await restoredClient.request('terminate', <String, Object?>{
        'sessionId': 'session-1',
      });
      expect(await restoredHarness.readHistory('session-1'), isNull);
    },
    skip: _skipTerminalHostRealPtyOnLinuxCiReason,
  );

  test(
    'pauses output per client and resumes with a host snapshot',
    () async {
      final harness = await _TerminalHostServerHarness.start();
      addTearDown(() async {
        await harness.dispose();
        if (await harness.tempDir.exists()) {
          await harness.tempDir.delete(recursive: true);
        }
      });

      final activeClient = await harness.connect();
      addTearDown(activeClient.dispose);
      await activeClient.hello(harness.token);
      final create = await activeClient.request('createOrAttach', <
        String,
        Object?
      >{
        'sessionId': 'paused-session',
        'workspaceId': 'workspace-1',
        'tabId': 'tab-1',
        'workingDirectory': Directory.current.path,
        'launch': const TerminalHostLaunch(
          label: 'shell',
          shell: '/bin/sh',
          arguments: <String>[
            '-c',
            r'printf ready; IFS= read -r line; printf "got:%s" "$line"; exit 0',
          ],
          environment: <String, String>{'TERM': 'xterm-256color'},
        ).toJson(),
        'cols': 80,
        'rows': 24,
      });
      expect(create['ok'], isTrue);
      expect(
        await activeClient.outputContaining('paused-session', 'ready'),
        contains('ready'),
      );

      final pausedClient = await harness.connect();
      addTearDown(pausedClient.dispose);
      await pausedClient.hello(harness.token);
      final attached = await pausedClient.request(
        'createOrAttach',
        <String, Object?>{
          'sessionId': 'paused-session',
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
      expect(attached.payload['created'], isFalse);
      await pausedClient.request('setOutputPaused', <String, Object?>{
        'sessionId': 'paused-session',
        'paused': true,
      });

      await activeClient.request('write', <String, Object?>{
        'sessionId': 'paused-session',
        'dataBase64': encodeTerminalHostBytes(utf8.encode('abc\r')),
      });
      expect(
        await activeClient.outputContaining('paused-session', 'got:abc'),
        contains('got:abc'),
      );
      await expectLater(
        pausedClient
            .event('output', sessionId: 'paused-session')
            .timeout(const Duration(milliseconds: 250)),
        throwsA(isA<TimeoutException>()),
      );

      final resumed = await pausedClient.request(
        'setOutputPaused',
        <String, Object?>{'sessionId': 'paused-session', 'paused': false},
      );
      expect(
        utf8.decode(decodeTerminalHostBytes(resumed.payload['snapshotBase64'])),
        contains('got:abc'),
      );
    },
    skip: _skipTerminalHostRealPtyOnLinuxCiReason,
  );

  test(
    'reports malformed requests and restores incomplete checkpoints',
    () async {
      final harness = await _TerminalHostServerHarness.start();
      addTearDown(() async {
        await harness.dispose();
        if (await harness.tempDir.exists()) {
          await harness.tempDir.delete(recursive: true);
        }
      });
      await harness.writeHistory(
        sessionId: 'restored-live',
        endedAt: null,
        buffer: utf8.encode('previous output'),
      );
      await harness.writeLegacyHistory(
        sessionId: 'legacy-json',
        contents: 'not json',
      );

      final unauthenticated = await harness.connect();
      addTearDown(unauthenticated.dispose);
      final denied = await unauthenticated.request('write', <String, Object?>{
        'sessionId': 'missing',
        'dataBase64': '',
      });
      expect(denied['ok'], isFalse);
      expect(denied['error'], contains('not authenticated'));

      final client = await harness.connect();
      addTearDown(client.dispose);
      await client.hello(harness.token);

      final restored = await client.request('createOrAttach', <String, Object?>{
        'sessionId': 'restored-live',
        'workspaceId': 'workspace-1',
        'tabId': 'tab-1',
        'workingDirectory': Directory.current.path,
        'launch': const TerminalHostLaunch(
          label: 'shell',
          shell: '/bin/sh',
          arguments: <String>['-c', 'exit 0'],
          environment: <String, String>{},
        ).toJson(),
      });
      expect(restored.payload['created'], isFalse);
      expect(restored.payload['running'], isFalse);
      expect(restored.payload['exitCode'], -1);
      expect(
        utf8.decode(
          decodeTerminalHostBytes(restored.payload['snapshotBase64']),
        ),
        'previous output',
      );
      final ignoredWrite = await client.request('write', <String, Object?>{
        'sessionId': 'restored-live',
        'dataBase64': '',
      });
      expect(ignoredWrite['ok'], isTrue);
      final ignoredResize = await client.request('resize', <String, Object?>{
        'sessionId': 'restored-live',
      });
      expect(ignoredResize['ok'], isTrue);

      final legacy = await client.request('createOrAttach', <String, Object?>{
        'sessionId': 'legacy-json',
        'workspaceId': 'workspace-1',
        'tabId': 'tab-2',
        'workingDirectory': Directory.current.path,
        'launch': const TerminalHostLaunch(
          label: 'shell',
          shell: '/bin/sh',
          arguments: <String>['-c', 'printf fresh'],
          environment: <String, String>{},
        ).toJson(),
      });
      expect(legacy.payload['created'], isTrue);

      final malformedCreate = await client.request(
        'createOrAttach',
        const <String, Object?>{'sessionId': 'bad'},
      );
      expect(malformedCreate['ok'], isFalse);
      expect(malformedCreate['error'], contains('session metadata'));

      final spawnFailure = await client
          .request('createOrAttach', <String, Object?>{
            'sessionId': 'spawn-failure',
            'workspaceId': 'workspace-1',
            'tabId': 'tab-3',
            'workingDirectory': Directory.current.path,
            'launch': const TerminalHostLaunch(
              label: 'missing shell',
              shell: '/definitely/not/alera-test-shell',
              arguments: <String>[],
              environment: <String, String>{},
            ).toJson(),
          });
      expect(spawnFailure['ok'], isFalse);

      final missingSession = await client.request('write', <String, Object?>{
        'sessionId': 'missing',
        'dataBase64': '',
      });
      expect(missingSession['ok'], isFalse);
      expect(
        missingSession['error'],
        'Terminal session is not attached: missing',
      );

      final unknown = await client.request(
        'unknown',
        const <String, Object?>{},
      );
      expect(unknown['ok'], isFalse);
      expect(unknown['error'], contains('Unknown terminal host request'));

      client.writeRaw(const <String, Object?>{
        'type': 'malformed',
        'payload': <String, Object?>{},
      });
      await expectLater(client.done, completes);
    },
    skip: _skipTerminalHostRealPtyOnLinuxCiReason,
  );

  test(
    'checkpoints long-running sessions and terminates active PTYs',
    () async {
      final harness = await _TerminalHostServerHarness.start();
      addTearDown(() async {
        await harness.dispose();
        if (await harness.tempDir.exists()) {
          await harness.tempDir.delete(recursive: true);
        }
      });
      final client = await harness.connect();
      addTearDown(client.dispose);
      await client.hello(harness.token);

      final created = await client.request('createOrAttach', <String, Object?>{
        'sessionId': 'running-checkpoint',
        'workspaceId': 'workspace-1',
        'tabId': 'tab-1',
        'workingDirectory': Directory.current.path,
        'launch': const TerminalHostLaunch(
          label: 'long running shell',
          shell: '/bin/sh',
          arguments: <String>['-c', 'printf tick; sleep 30'],
          environment: <String, String>{},
        ).toJson(),
      });
      expect(created.payload['created'], isTrue);
      expect(
        await client.outputContaining('running-checkpoint', 'tick'),
        contains('tick'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5200));
      expect(await harness.historyDatabaseFile.exists(), isTrue);
      final checkpoint = await harness.readHistory('running-checkpoint');
      expect(checkpoint, isNotNull);
      expect(checkpoint!.running, isTrue);
      expect(utf8.decode(checkpoint.buffer), contains('tick'));

      final terminate = await client.request('terminate', <String, Object?>{
        'sessionId': 'running-checkpoint',
      });
      expect(terminate['ok'], isTrue);
      expect(await harness.readHistory('running-checkpoint'), isNull);
    },
    skip: _skipTerminalHostRealPtyOnLinuxCiReason,
  );
}
