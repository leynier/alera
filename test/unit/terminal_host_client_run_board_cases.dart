part of 'terminal_host_client_test.dart';

void _registerTerminalHostClientRunBoardTests() {
  for (final supported in [false, true]) {
    test(
      'negotiates run board capability without upgrading the protocol: $supported',
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

Future<void> _writeControlFile({
  required Directory tempDir,
  String fileName = 'host.json',
  required int port,
  required String token,
  int protocolVersion = aleraTerminalHostProtocolVersion,
  bool includeRuntimeCapability = true,
  bool includeBootstrapCapability = true,
  bool includeManagedWorkspaceCapability = true,
  bool includeOrchestrationCapability = true,
  bool includeBinaryFramesCapability = false,
  bool includeRunBoardCapability = false,
}) async {
  final runtimeDir = Directory(p.join(tempDir.path, 'terminal_host'));
  await runtimeDir.create(recursive: true);
  final payload = <String, Object?>{
    'protocolVersion': protocolVersion,
    'port': port,
    'token': token,
  };
  final capabilities = <String>[
    if (includeRuntimeCapability) ...<String>[
      aleraRuntimeHostCapability,
      if (includeBootstrapCapability) aleraRuntimeHostBootstrapCapability,
      if (includeManagedWorkspaceCapability)
        aleraRuntimeHostManagedWorkspaceCapability,
      if (includeOrchestrationCapability)
        aleraRuntimeHostOrchestrationCapability,
      if (includeBinaryFramesCapability) aleraRuntimeHostBinaryFramesCapability,
      if (includeRunBoardCapability) aleraRuntimeHostRunBoardCapability,
    ],
  ];
  if (capabilities.isNotEmpty) {
    payload['runtimeCapabilities'] = capabilities;
  }
  await File(
    p.join(runtimeDir.path, fileName),
  ).writeAsString(jsonEncode(payload));
}
