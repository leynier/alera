import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
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
            r'IFS= read line; printf "got:%s" "$line"; exit 7',
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
    },
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
      await harness.writeRawHistory(sessionId: 'corrupt', contents: 'not json');

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

      final corrupt = await client.request('createOrAttach', <String, Object?>{
        'sessionId': 'corrupt',
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
      expect(corrupt.payload['created'], isTrue);

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
      final sessionsDir = Directory(
        p.join(harness.runtimeDir.path, 'sessions'),
      );
      await sessionsDir.delete(recursive: true);

      final created = await client.request('createOrAttach', <String, Object?>{
        'sessionId': 'running-checkpoint',
        'workspaceId': 'workspace-1',
        'tabId': 'tab-1',
        'workingDirectory': Directory.current.path,
        'launch': const TerminalHostLaunch(
          label: 'long running shell',
          shell: '/bin/sh',
          arguments: <String>['-c', 'printf tick; sleep 5'],
          environment: <String, String>{},
        ).toJson(),
      });
      expect(created.payload['created'], isTrue);
      expect(
        await client.outputContaining('running-checkpoint', 'tick'),
        contains('tick'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 5200));
      expect(
        await File(
          p.join(
            sessionsDir.path,
            '${Uri.encodeComponent('running-checkpoint')}.json',
          ),
        ).exists(),
        isTrue,
      );

      final terminate = await client.request('terminate', <String, Object?>{
        'sessionId': 'running-checkpoint',
      });
      expect(terminate['ok'], isTrue);
    },
  );

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
      final history = Map<String, Object?>.from(
        jsonDecode(await harness.historyFile('detached-running').readAsString())
            as Map,
      );
      expect(history['running'], isFalse);
      expect(history['endedAt'], isNotNull);
      expect(
        utf8.decode(decodeTerminalHostBytes(history['bufferBase64'])),
        contains('still-running'),
      );
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

final class _TerminalHostServerHarness {
  _TerminalHostServerHarness._({
    required this.tempDir,
    required this.runtimeDir,
    required this.controlFile,
    required this.token,
    required this._server,
    required this._runFuture,
  });

  static Future<_TerminalHostServerHarness> start({
    Directory? tempDir,
    String token = 'token-1',
    TerminalHostConfig config = TerminalHostConfig.defaults,
  }) async {
    final root =
        tempDir ?? await Directory.systemTemp.createTemp('alera-host-server-');
    final runtimeDir = Directory(p.join(root.path, 'terminal_host'));
    final controlFile = File(p.join(runtimeDir.path, 'host.json'));
    if (await controlFile.exists()) {
      await controlFile.delete();
    }
    final server = AleraTerminalHostServer(
      runtimeDir: runtimeDir.path,
      controlFilePath: controlFile.path,
      token: token,
      config: config,
    );
    final runFuture = server.run();
    final harness = _TerminalHostServerHarness._(
      tempDir: root,
      runtimeDir: runtimeDir,
      controlFile: controlFile,
      token: token,
      server: server,
      runFuture: runFuture,
    );
    await harness._waitForControlFile();
    return harness;
  }

  final Directory tempDir;
  final Directory runtimeDir;
  final File controlFile;
  final String token;
  final AleraTerminalHostServer _server;
  final Future<void> _runFuture;
  bool _disposed = false;

  Future<_TerminalHostJsonClient> connect() async {
    final control = Map<String, Object?>.from(
      jsonDecode(await controlFile.readAsString()) as Map,
    );
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      control['port']! as int,
    );
    return _TerminalHostJsonClient(socket);
  }

  Future<void> writeHistory({
    required String sessionId,
    required DateTime? endedAt,
    required List<int> buffer,
  }) async {
    final file = _historyFile(sessionId);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'protocolVersion': aleraTerminalHostProtocolVersion,
        'sessionId': sessionId,
        'workspaceId': 'workspace-1',
        'tabId': 'tab-1',
        'workingDirectory': Directory.current.path,
        'running': false,
        'exitCode': null,
        'endedAt': endedAt?.toIso8601String(),
        'bufferBase64': encodeTerminalHostBytes(buffer),
      }),
    );
  }

  Future<void> writeRawHistory({
    required String sessionId,
    required String contents,
  }) async {
    final file = _historyFile(sessionId);
    await file.parent.create(recursive: true);
    await file.writeAsString(contents);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _server.dispose();
    await _runFuture.timeout(const Duration(seconds: 2));
  }

  Future<void> waitForStop() async {
    await _runFuture.timeout(const Duration(seconds: 5));
  }

  Future<void> _waitForControlFile() async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (await controlFile.exists()) {
        final control = Map<String, Object?>.from(
          jsonDecode(await controlFile.readAsString()) as Map,
        );
        if (control['token'] == token) {
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    throw StateError('terminal host test server did not publish control file');
  }

  File historyFile(String sessionId) {
    return File(
      p.join(
        runtimeDir.path,
        'sessions',
        '${Uri.encodeComponent(sessionId)}.json',
      ),
    );
  }

  File _historyFile(String sessionId) {
    return historyFile(sessionId);
  }
}

final class _TerminalHostJsonClient {
  _TerminalHostJsonClient(this._socket) {
    _sub = _socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine, onDone: _completeDone, onError: _completeDone);
  }

  final Socket _socket;
  final Map<int, Completer<Map<String, Object?>>> _responses =
      <int, Completer<Map<String, Object?>>>{};
  final List<Map<String, Object?>> _queuedEvents = <Map<String, Object?>>[];
  final List<Completer<Map<String, Object?>>> _eventWaiters =
      <Completer<Map<String, Object?>>>[];
  final Completer<void> _done = Completer<void>();
  late final StreamSubscription<String> _sub;
  int _nextId = 1;

  Future<void> get done => _done.future.timeout(const Duration(seconds: 5));

  Future<Map<String, Object?>> hello(String token) {
    return _requestWithId(0, 'hello', <String, Object?>{
      'protocolVersion': aleraTerminalHostProtocolVersion,
      'token': token,
    });
  }

  Future<Map<String, Object?>> request(
    String type,
    Map<String, Object?> payload,
  ) {
    return _requestWithId(_nextId++, type, payload);
  }

  Future<Map<String, Object?>> event(String type, {String? sessionId}) async {
    while (true) {
      final event = _queuedEvents.isNotEmpty
          ? _queuedEvents.removeAt(0)
          : await _waitForEvent();
      if (event['event'] != type) {
        continue;
      }
      final payload = event.payload;
      if (sessionId == null || payload['sessionId'] == sessionId) {
        return event;
      }
    }
  }

  Future<String> outputContaining(String sessionId, String expected) async {
    final buffer = StringBuffer();
    while (!buffer.toString().contains(expected)) {
      final event = await this.event('output', sessionId: sessionId);
      buffer.write(
        utf8.decode(decodeTerminalHostBytes(event.payload['dataBase64'])),
      );
    }
    return buffer.toString();
  }

  void writeRaw(Map<String, Object?> message) {
    _socket.writeln(jsonEncode(message));
  }

  Future<void> dispose() async {
    await _sub.cancel();
    _socket.destroy();
    _completeDone();
  }

  Future<Map<String, Object?>> _requestWithId(
    int id,
    String type,
    Map<String, Object?> payload,
  ) {
    final completer = Completer<Map<String, Object?>>();
    _responses[id] = completer;
    writeRaw(<String, Object?>{'id': id, 'type': type, 'payload': payload});
    return completer.future.timeout(const Duration(seconds: 5));
  }

  void _handleLine(String line) {
    final message = Map<String, Object?>.from(jsonDecode(line) as Map);
    if (message.containsKey('event')) {
      if (_eventWaiters.isEmpty) {
        _queuedEvents.add(message);
      } else {
        _eventWaiters.removeAt(0).complete(message);
      }
      return;
    }
    final id = message['id'];
    if (id is int) {
      _responses.remove(id)?.complete(message);
    }
  }

  void _completeDone([Object? error]) {
    if (!_done.isCompleted) {
      _done.complete();
    }
  }

  Future<Map<String, Object?>> _waitForEvent() {
    final completer = Completer<Map<String, Object?>>();
    _eventWaiters.add(completer);
    return completer.future.timeout(const Duration(seconds: 5));
  }
}
