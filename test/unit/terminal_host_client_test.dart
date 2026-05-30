import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_client.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghostty_vte_flutter/ghostty_vte_flutter.dart';
import 'package:path/path.dart' as p;

void main() {
  test('connects through launcher and sends lifecycle requests', () async {
    final tempDir = await Directory.systemTemp.createTemp('alera-host-client-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final server = await _TerminalHostTestServer.start();
    addTearDown(server.dispose);
    final launcher = _FakeTerminalHostLauncher(server: server);
    final client = SocketTerminalHostClient(
      launcher: launcher,
      applicationSupportDirectory: () async => tempDir,
    );
    addTearDown(client.dispose);
    final outputEvent = client.events
        .where((event) => event is TerminalHostOutputEvent)
        .cast<TerminalHostOutputEvent>()
        .first;
    final exitEvent = client.events
        .where((event) => event is TerminalHostExitEvent)
        .cast<TerminalHostExitEvent>()
        .first;
    final errorEvent = client.events
        .where((event) => event is TerminalHostErrorEvent)
        .cast<TerminalHostErrorEvent>()
        .first;

    final attachment = await client.createOrAttach(
      sessionId: 'session-1',
      workspaceId: 'workspace-1',
      tabId: 'tab-1',
      workingDirectory: '/repo',
      launch: _launch(setupCommand: 'echo setup\n'),
      cols: 80,
      rows: 24,
    );
    await client.write(sessionId: 'session-1', bytes: const <int>[]);
    await client.write(sessionId: 'session-1', bytes: const <int>[1, 2]);
    await client.resize(sessionId: 'session-1', cols: 120, rows: 40);
    final snapshot = await client.setOutputPaused(
      sessionId: 'session-1',
      paused: false,
    );
    await client.detach('session-1');
    await client.terminate('session-1');

    server.send(<String, Object?>{
      'event': 'output',
      'payload': <String, Object?>{
        'sessionId': 'session-1',
        'dataBase64': encodeTerminalHostBytes(<int>[65]),
      },
    });
    server.send(<String, Object?>{
      'event': 'exit',
      'payload': <String, Object?>{'sessionId': 'session-1', 'exitCode': 7},
    });
    server.send(<String, Object?>{
      'event': 'error',
      'payload': <String, Object?>{'sessionId': 'session-1', 'error': 'boom'},
    });

    expect(launcher.starts, 1);
    expect(
      launcher.configs.single.toJson(),
      TerminalHostConfig.defaults.toJson(),
    );
    expect(attachment.sessionId, 'session-1');
    expect(attachment.created, isTrue);
    expect(attachment.running, isTrue);
    expect(attachment.snapshot, <int>[65, 66]);
    expect(snapshot, <int>[83, 78, 65, 80]);
    expect(server.requestTypes, <String>[
      'hello',
      'createOrAttach',
      'write',
      'resize',
      'setOutputPaused',
      'detach',
      'terminate',
    ]);
    final createPayload = server.payloadFor('createOrAttach');
    expect(createPayload['workingDirectory'], '/repo');
    expect(createPayload['cols'], 80);
    expect(createPayload['rows'], 24);
    expect(
      createPayload['launch'],
      isNot(containsPair('setupCommand', anything)),
    );
    expect(
      server.payloadFor('write')['dataBase64'],
      encodeTerminalHostBytes(<int>[1, 2]),
    );
    expect(server.payloadFor('setOutputPaused'), <String, Object?>{
      'sessionId': 'session-1',
      'paused': false,
    });
    expect((await outputEvent).data, <int>[65]);
    expect((await exitEvent).exitCode, 7);
    expect((await errorEvent).error, 'boom');

    client.dispose();
    client.dispose();
  });

  test('ensureStarted launches the host and sends initial config', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-warmup-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final server = await _TerminalHostTestServer.start();
    addTearDown(server.dispose);
    final launcher = _FakeTerminalHostLauncher(server: server);
    final client = SocketTerminalHostClient(
      launcher: launcher,
      applicationSupportDirectory: () async => tempDir,
    );
    addTearDown(client.dispose);
    const config = TerminalHostConfig(
      emptyShutdownDelaySeconds: 5,
      detachedSessionShutdownDelaySeconds: 10,
      scrollbackBytes: 1024,
    );

    await client.ensureStarted(config: config);

    expect(launcher.starts, 1);
    expect(launcher.configs.single.toJson(), config.toJson());
    expect(server.requestTypes, <String>['hello', 'configure']);
    expect(server.payloadFor('configure'), config.toJson());
  });

  test(
    'configure updates connected hosts but does not start idle ones',
    () async {
      final idleTempDir = await Directory.systemTemp.createTemp(
        'alera-host-client-config-idle-',
      );
      final activeTempDir = await Directory.systemTemp.createTemp(
        'alera-host-client-config-active-',
      );
      addTearDown(() async {
        if (await idleTempDir.exists()) {
          await idleTempDir.delete(recursive: true);
        }
        if (await activeTempDir.exists()) {
          await activeTempDir.delete(recursive: true);
        }
      });
      final idleLauncher = _NoopTerminalHostLauncher();
      final idleClient = SocketTerminalHostClient(
        launcher: idleLauncher,
        applicationSupportDirectory: () async => idleTempDir,
      );
      addTearDown(idleClient.dispose);
      const config = TerminalHostConfig(
        emptyShutdownDelaySeconds: 6,
        detachedSessionShutdownDelaySeconds: 12,
        scrollbackBytes: 2048,
      );

      await idleClient.configure(config);

      expect(idleLauncher.starts, 0);

      final server = await _TerminalHostTestServer.start();
      addTearDown(server.dispose);
      await _writeControlFile(
        tempDir: activeTempDir,
        port: server.port,
        token: 'existing-token',
      );
      final activeClient = SocketTerminalHostClient(
        launcher: _NoopTerminalHostLauncher(),
        applicationSupportDirectory: () async => activeTempDir,
      );
      addTearDown(activeClient.dispose);

      await activeClient.ensureStarted(config: TerminalHostConfig.defaults);
      await activeClient.configure(config);

      expect(server.requestTypes, <String>['hello', 'configure', 'configure']);
      expect(server.payloadFor('configure'), config.toJson());
    },
  );

  test('reuses an existing control file and surfaces host errors', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-existing-',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final server = await _TerminalHostTestServer.start(errorForType: 'resize');
    addTearDown(server.dispose);
    await _writeControlFile(
      tempDir: tempDir,
      port: server.port,
      token: 'existing-token',
    );
    final launcher = _FakeTerminalHostLauncher(server: server);
    final client = SocketTerminalHostClient(
      launcher: launcher,
      applicationSupportDirectory: () async => tempDir,
    );
    addTearDown(client.dispose);

    await client.write(sessionId: 'session-1', bytes: const <int>[1]);
    await expectLater(
      client.resize(sessionId: 'session-1', cols: 100, rows: 30),
      throwsA(isA<StateError>()),
    );

    expect(launcher.starts, 0);
    expect(server.requestTypes.take(2), <String>['hello', 'write']);
  });

  test('fails pending requests when the host closes the socket', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'alera-host-client-closes-',
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
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('connection closed'),
        ),
      ),
    );
  });

  test(
    'deletes stale controls and times out when launch does not publish one',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'alera-host-client-stale-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      await _writeControlFile(tempDir: tempDir, port: 1, token: 'stale-token');
      final client = SocketTerminalHostClient(
        launcher: _NoopTerminalHostLauncher(),
        applicationSupportDirectory: () async => tempDir,
        startupTimeout: Duration.zero,
      );
      addTearDown(client.dispose);

      await expectLater(
        client.detach('session-1'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('did not start in time'),
          ),
        ),
      );

      final controlFile = File(
        p.join(tempDir.path, 'terminal_host', 'host.json'),
      );
      expect(await controlFile.exists(), isFalse);
    },
  );

  test('rejects requests after disposal', () async {
    final client = SocketTerminalHostClient(
      launcher: _NoopTerminalHostLauncher(),
      applicationSupportDirectory: () async => Directory.systemTemp,
    );

    client.dispose();

    await expectLater(
      client.write(sessionId: 'session-1', bytes: const <int>[1]),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      client.configure(TerminalHostConfig.defaults),
      throwsA(isA<StateError>()),
    );
  });
}

GhosttyTerminalShellLaunch _launch({String? setupCommand}) {
  return GhosttyTerminalShellLaunch(
    label: 'shell',
    shell: '/bin/sh',
    arguments: const <String>['-l'],
    environment: const <String, String>{'TERM': 'xterm-256color'},
    setupCommand: setupCommand,
  );
}

Future<void> _writeControlFile({
  required Directory tempDir,
  required int port,
  required String token,
}) async {
  final runtimeDir = Directory(p.join(tempDir.path, 'terminal_host'));
  await runtimeDir.create(recursive: true);
  await File(p.join(runtimeDir.path, 'host.json')).writeAsString(
    jsonEncode(<String, Object?>{
      'protocolVersion': aleraTerminalHostProtocolVersion,
      'port': port,
      'token': token,
    }),
  );
}

final class _FakeTerminalHostLauncher implements TerminalHostProcessLauncher {
  _FakeTerminalHostLauncher({required this.server});

  final _TerminalHostTestServer server;
  int starts = 0;
  final List<TerminalHostConfig> configs = <TerminalHostConfig>[];

  @override
  Future<void> start({
    required String runtimeDir,
    required String controlFilePath,
    required String token,
    required TerminalHostConfig config,
  }) async {
    starts += 1;
    configs.add(config);
    server.token = token;
    await File(controlFilePath).parent.create(recursive: true);
    await File(controlFilePath).writeAsString(
      jsonEncode(<String, Object?>{
        'protocolVersion': aleraTerminalHostProtocolVersion,
        'port': server.port,
        'token': token,
      }),
    );
  }
}

final class _NoopTerminalHostLauncher implements TerminalHostProcessLauncher {
  int starts = 0;

  @override
  Future<void> start({
    required String runtimeDir,
    required String controlFilePath,
    required String token,
    required TerminalHostConfig config,
  }) async {
    starts += 1;
  }
}

final class _TerminalHostTestServer {
  _TerminalHostTestServer._(
    this._server, {
    this.errorForType,
    this.closeForType,
  });

  static Future<_TerminalHostTestServer> start({
    String? errorForType,
    String? closeForType,
  }) async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final server = _TerminalHostTestServer._(
      socket,
      errorForType: errorForType,
      closeForType: closeForType,
    );
    server._sub = socket.listen(server._accept, onError: (_) {});
    return server;
  }

  final ServerSocket _server;
  final String? errorForType;
  final String? closeForType;
  final List<Map<String, Object?>> requests = <Map<String, Object?>>[];
  StreamSubscription<Socket>? _sub;
  Socket? _client;
  String token = 'existing-token';

  int get port => _server.port;

  List<String> get requestTypes {
    return <String>[for (final request in requests) request['type']! as String];
  }

  Map<String, Object?> payloadFor(String type) {
    return requests
        .where((request) => request['type'] == type)
        .map((request) => request['payload']! as Map<String, Object?>)
        .last;
  }

  void _accept(Socket socket) {
    _client = socket;
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine, onError: (_) {});
  }

  void _handleLine(String line) {
    final request = Map<String, Object?>.from(jsonDecode(line) as Map);
    final payload = Map<String, Object?>.from(request['payload'] as Map);
    request['payload'] = payload;
    requests.add(request);
    final id = request['id'] as int;
    final type = request['type'] as String;
    if (type == closeForType) {
      _client!.destroy();
      return;
    }
    if (type == errorForType) {
      _client!.writeln(
        jsonEncode(<String, Object?>{
          'id': id,
          'ok': false,
          'error': '$type failed',
        }),
      );
      return;
    }
    if (type == 'createOrAttach') {
      _client!.writeln(
        jsonEncode(<String, Object?>{
          'id': id,
          'ok': true,
          'payload': <String, Object?>{
            'sessionId': 'session-1',
            'created': true,
            'running': true,
            'snapshotBase64': encodeTerminalHostBytes(<int>[65, 66]),
          },
        }),
      );
      return;
    }
    if (type == 'setOutputPaused') {
      _client!.writeln(
        jsonEncode(<String, Object?>{
          'id': id,
          'ok': true,
          'payload': <String, Object?>{
            'sessionId': 'session-1',
            'snapshotBase64': encodeTerminalHostBytes(<int>[83, 78, 65, 80]),
          },
        }),
      );
      return;
    }
    _client!.writeln(
      jsonEncode(<String, Object?>{
        'id': id,
        'ok': true,
        'payload': const <String, Object?>{},
      }),
    );
  }

  void send(Map<String, Object?> message) {
    _client!.writeln(jsonEncode(message));
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _client?.destroy();
    await _server.close();
  }
}
