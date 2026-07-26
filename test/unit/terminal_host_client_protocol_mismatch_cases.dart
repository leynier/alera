part of 'terminal_host_client_test.dart';

/// A live host speaking another protocol version owns the runtime directory.
///
/// `_readControl` answers null for that file, exactly as it does for no file at
/// all, so the client used to launch anyway, re-read the same incompatible file
/// every hundred milliseconds, and fail the whole startup timeout later with
/// "did not start in time" and no last error. The cause was knowable at the
/// first read. Arriving here is ordinary: an app update leaves the previous
/// `alera terminal-host` running, which is what `make host-stop` is for.
void _registerTerminalHostClientProtocolMismatchTests() {
  test(
    'a live host of another protocol version is reported, not launched',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-host-client-mismatch-',
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
        protocolVersion: aleraTerminalHostProtocolVersion + 1,
      );
      final launcher = _NoopTerminalHostLauncher();
      final client = SocketTerminalHostClient(
        launcher: launcher,
        applicationSupportDirectory: () async => tempDir,
        // Long enough that a test finishing quickly proves the timeout was never
        // waited out.
        startupTimeout: const Duration(minutes: 5),
      );
      addTearDown(client.dispose);

      await expectLater(
        client.ensureStarted(config: TerminalHostConfig.defaults),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('${aleraTerminalHostProtocolVersion + 1}'),
              contains('host-stop'),
            ),
          ),
        ),
      );
      expect(
        launcher.starts,
        0,
        reason: 'launched a second host into a directory another host owns',
      );
    },
  );

  test(
    'a stale control file of another version does not block a launch',
    () async {
      // The host that wrote it is gone, so the file is leftover rather than
      // evidence of an owner. Refusing here would turn a crashed old host into a
      // permanently unusable runtime directory.
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-host-client-stale-mismatch-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final deadServer = await _TerminalHostTestServer.start();
      final deadPort = deadServer.port;
      await deadServer.dispose();
      await _writeControlFile(
        tempDir: tempDir,
        port: deadPort,
        token: 'stale-token',
        protocolVersion: aleraTerminalHostProtocolVersion + 1,
      );
      final server = await _TerminalHostTestServer.start();
      addTearDown(server.dispose);
      final launcher = _FakeTerminalHostLauncher(server: server);
      final client = SocketTerminalHostClient(
        launcher: launcher,
        applicationSupportDirectory: () async => tempDir,
      );
      addTearDown(client.dispose);

      await client.ensureStarted(config: TerminalHostConfig.defaults);

      expect(launcher.starts, 1);
    },
  );
}
