part of 'terminal_host_client_test.dart';

void _registerTerminalHostClientRunBoardTests() {
  for (final (supported, sections) in [
    for (final board in [false, true])
      for (final sections in [false, true]) (board, sections),
  ]) {
    test(
      'negotiates independent board/sections capabilities: $supported/$sections',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'alera-run-board-client-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final server = await _TerminalHostTestServer.start();
        addTearDown(server.dispose);
        await _writeControlFile(
          tempDir: directory,
          port: server.port,
          token: 'test-token',
          includeRunBoardCapability: supported,
          includeWorkspaceSectionsCapability: sections,
        );
        final launcher = _NoopTerminalHostLauncher();
        final client = SocketTerminalHostClient(
          launcher: launcher,
          applicationSupportDirectory: () async => directory,
        );
        addTearDown(client.dispose);
        expect(
          await client.supportsRuntimeCapability(
            aleraRuntimeHostRunBoardCapability,
          ),
          supported,
        );
        expect(
          await client.supportsRuntimeCapability(
            aleraRuntimeHostWorkspaceSectionsCapability,
          ),
          sections,
        );
        expect(
          await client.supportsRuntimeCapability('unknown-capability'),
          isFalse,
        );
        expect(
          launcher.starts,
          0,
          reason: 'an old host remains usable without board support',
        );
        final disconnected = client.runtimeEvents.firstWhere(
          (event) => event.name == aleraRuntimeHostDisconnectedEvent,
        );
        server.closeClient();
        await disconnected.timeout(const Duration(seconds: 5));
      },
    );
  }

  for (final binaryFrames in [false, true]) {
    test(
      'forwards board revisions over socket frames: $binaryFrames',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'alera-run-board-events-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final server = await _TerminalHostTestServer.start(
          negotiateBinaryFrames: true,
        );
        addTearDown(server.dispose);
        await _writeControlFile(
          tempDir: directory,
          port: server.port,
          token: 'test-token',
          includeRunBoardCapability: true,
          includeBinaryFramesCapability: binaryFrames,
        );
        final client = SocketTerminalHostClient(
          launcher: _NoopTerminalHostLauncher(),
          applicationSupportDirectory: () async => directory,
        );
        addTearDown(client.dispose);
        expect(
          await client.supportsRuntimeCapability(
            aleraRuntimeHostRunBoardCapability,
          ),
          isTrue,
        );
        expect(server.usingBinaryFrames, binaryFrames);
        final changed = client.runtimeEvents.firstWhere(
          (event) => event.name == 'orchestrationBoardChanged',
        );
        server.send({
          'event': 'orchestrationBoardChanged',
          'payload': {'revision': 42},
        });
        final event = await changed.timeout(const Duration(seconds: 5));
        expect(event.name, 'orchestrationBoardChanged');
        expect(event.payload, {'revision': 42});
      },
    );
  }
}
