part of 'terminal_host_client_test.dart';

void _registerTerminalHostBufferGuardTests() {
  for (final duringHello in [false, true]) {
    test(
      'freezes and acknowledges editor buffers ${duringHello ? 'during reconnect' : 'on request'}',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'alera-buffer-client-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final acknowledged = Completer<void>();
        final server = await _TerminalHostTestServer.start(
          beforeResponse: (type) async {
            if (type == 'workspace.bufferGuard.ack' &&
                !acknowledged.isCompleted) {
              acknowledged.complete();
            }
          },
        );
        addTearDown(server.dispose);
        const guard = <String, Object?>{
          'guardId': 'guard',
          'scope': {
            'tabIds': ['editor'],
            'workspacePaths': ['/repo'],
          },
        };
        if (duringHello) {
          server.helloPayload = {
            'checkoutBufferGuards': [guard],
          };
        }
        final handler = _RecordingBufferGuardHandler();
        final client = SocketTerminalHostClient(
          launcher: _FakeTerminalHostLauncher(server: server),
          applicationSupportDirectory: () async => directory,
          bufferGuardHandler: handler,
        );
        addTearDown(client.dispose);
        await client.ensureStarted(config: TerminalHostConfig.defaults);
        if (!duringHello) {
          server.send({'event': 'checkoutBuffersLock', 'payload': guard});
        }
        await acknowledged.future.timeout(const Duration(seconds: 5));
        expect(server.payloadFor('hello')['checkoutBufferGuardsV1'], isTrue);
        expect(handler.tabIds, {'editor'});
        expect(handler.workspacePaths, {'/repo'});
        expect(server.payloadFor('workspace.bufferGuard.ack'), {
          'guardId': 'guard',
          'blockers': [],
        });
        server.send({
          'event': 'checkoutBuffersReleased',
          'payload': {'guardId': 'guard'},
        });
        expect(
          await handler.released.future.timeout(const Duration(seconds: 5)),
          'guard',
        );
      },
    );
  }
}

class _RecordingBufferGuardHandler implements RuntimeBufferGuardHandler {
  Set<String>? tabIds;
  Set<String>? workspacePaths;
  final released = Completer<String>();

  @override
  List<Map<String, Object?>> lock({
    required String guardId,
    required Set<String> tabIds,
    required Set<String> workspacePaths,
  }) {
    this.tabIds = tabIds;
    this.workspacePaths = workspacePaths;
    return [];
  }

  @override
  void release(String guardId, {bool retired = false}) {
    if (!released.isCompleted) released.complete(guardId);
  }
}
