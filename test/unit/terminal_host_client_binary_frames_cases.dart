part of 'terminal_host_client_test.dart';

Future<SocketTerminalHostClient> _binaryClient(
  _TerminalHostTestServer server, {
  required bool advertiseCapability,
}) async {
  final tempDir = await Directory.systemTemp.createTemp('alera-host-binary-');
  addTearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });
  await _writeControlFile(
    tempDir: tempDir,
    port: server.port,
    token: 'existing-token',
    includeBinaryFramesCapability: advertiseCapability,
  );
  final client = SocketTerminalHostClient(
    launcher: _NoopTerminalHostLauncher(),
    applicationSupportDirectory: () async => tempDir,
  );
  addTearDown(client.dispose);
  return client;
}

void _registerTerminalHostClientBinaryFrameTests() {
  test('negotiates frames and receives raw output', () async {
    final server = await _TerminalHostTestServer.start(
      negotiateBinaryFrames: true,
    );
    addTearDown(server.dispose);
    final client = await _binaryClient(server, advertiseCapability: true);

    await client.runtimeRequest('status.get');
    expect(
      server.payloadFor('hello')['binaryFrames'],
      isTrue,
      reason: 'the client must ask for the upgrade it is capable of',
    );
    expect(server.usingBinaryFrames, isTrue);

    final output = client
        .eventsForSession('session-1')
        .where((event) => event is TerminalHostOutputEvent)
        .cast<TerminalHostOutputEvent>()
        .first;
    // Bytes that are not valid UTF-8 and would not survive a JSON round-trip
    // without base64. Here they travel raw.
    server.sendOutput('session-1', <int>[0x1b, 0x5b, 0x6d, 0xff, 0x00]);

    expect((await output).data, <int>[0x1b, 0x5b, 0x6d, 0xff, 0x00]);
  });

  test('control events still arrive once framed', () async {
    final server = await _TerminalHostTestServer.start(
      negotiateBinaryFrames: true,
    );
    addTearDown(server.dispose);
    final client = await _binaryClient(server, advertiseCapability: true);
    await client.runtimeRequest('status.get');

    final runtimeEvent = client.runtimeEvents.first;
    server.send(<String, Object?>{
      'event': 'agentPresenceChanged',
      'payload': <String, Object?>{},
    });

    expect((await runtimeEvent).name, 'agentPresenceChanged');
  });

  test('a host without the capability keeps JSON lines', () async {
    // The compatibility case that matters most: attaching to an older sidecar
    // that is already running must not change anything.
    final server = await _TerminalHostTestServer.start(
      negotiateBinaryFrames: true,
    );
    addTearDown(server.dispose);
    final client = await _binaryClient(server, advertiseCapability: false);

    await client.runtimeRequest('status.get');
    expect(server.payloadFor('hello').containsKey('binaryFrames'), isFalse);
    expect(server.usingBinaryFrames, isFalse);

    final output = client
        .eventsForSession('session-1')
        .where((event) => event is TerminalHostOutputEvent)
        .cast<TerminalHostOutputEvent>()
        .first;
    server.sendOutput('session-1', <int>[1, 2, 3]);

    expect((await output).data, <int>[1, 2, 3]);
  });

  test('a host that declines the upgrade keeps JSON lines', () async {
    final server = await _TerminalHostTestServer.start();
    addTearDown(server.dispose);
    final client = await _binaryClient(server, advertiseCapability: true);

    await client.runtimeRequest('status.get');
    expect(server.payloadFor('hello')['binaryFrames'], isTrue);
    expect(
      server.usingBinaryFrames,
      isFalse,
      reason: 'asking is not enough; the response decides',
    );

    final output = client
        .eventsForSession('session-1')
        .where((event) => event is TerminalHostOutputEvent)
        .cast<TerminalHostOutputEvent>()
        .first;
    server.sendOutput('session-1', <int>[4, 5]);

    expect((await output).data, <int>[4, 5]);
  });
}
