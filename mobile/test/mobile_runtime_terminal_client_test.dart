import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// A loopback gateway that records every request and answers each one with a
/// payload chosen by [reply].
class _FakeGateway {
  _FakeGateway._(this._server, this.requests);

  static Future<_FakeGateway> start({
    required Map<String, Object?> Function(Map<String, Object?> request) reply,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Map<String, Object?>>[];
    final gateway = _FakeGateway._(server, requests);
    gateway._subscription = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      gateway._sockets.add(socket);
      socket.listen((raw) {
        final message = jsonDecode(raw as String) as Map<String, Object?>;
        requests.add(message);
        socket.add(
          jsonEncode(<String, Object?>{
            'id': message['id'],
            'ok': true,
            'payload': reply(message),
          }),
        );
      });
    });
    return gateway;
  }

  final HttpServer _server;
  final List<Map<String, Object?>> requests;
  final List<WebSocket> _sockets = <WebSocket>[];
  StreamSubscription<HttpRequest>? _subscription;

  String get endpoint => 'ws://${_server.address.address}:${_server.port}';

  void emit(String event, Map<String, Object?> payload) {
    for (final socket in _sockets) {
      socket.add(
        jsonEncode(<String, Object?>{'event': event, 'payload': payload}),
      );
    }
  }

  Future<void> closeSockets() async {
    for (final socket in _sockets) {
      await socket.close();
    }
    _sockets.clear();
  }

  Future<void> dispose() async {
    await closeSockets();
    await _subscription?.cancel();
    await _server.close(force: true);
  }

  List<Map<String, Object?>> requestsOfType(String type) {
    return requests.where((request) => request['type'] == type).toList();
  }

  Map<String, Object?> payloadOf(Map<String, Object?> request) {
    return (request['payload'] as Map<String, Object?>?) ??
        const <String, Object?>{};
  }
}

/// Polls [condition] until it holds. The gateway answers over a real loopback
/// socket, so a fixed number of event-queue drains is a race.
Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition was not met within $timeout.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  group('Terminal input', () {
    test(
      'Feature detects deferred terminal input during the handshake',
      () async {
        final gateway = await _FakeGateway.start(
          reply: (_) => <String, Object?>{
            'runtimeCapabilities': <String>[terminalDeferredInputCapability],
          },
        );
        addTearDown(gateway.dispose);
        final client = await MobileRuntimeClient.connect(gateway.endpoint);
        addTearDown(client.dispose);

        expect(client.supportsDeferredTerminalInput, isFalse);
        await client.authenticate(deviceId: 'device-1', deviceToken: 'token-1');
        expect(client.supportsDeferredTerminalInput, isTrue);
      },
    );

    test('Write forwards the flags and omits them when false', () async {
      final gateway = await _FakeGateway.start(
        reply: (_) => const <String, Object?>{},
      );
      addTearDown(gateway.dispose);
      final client = await MobileRuntimeClient.connect(gateway.endpoint);
      addTearDown(client.dispose);

      await client.writeTerminal('session-1', utf8.encode('ls'));
      await client.writeTerminal(
        'session-1',
        utf8.encode('first\nsecond'),
        bracketedPaste: true,
        deferredEnter: true,
      );

      final writes = gateway.requestsOfType('write');
      expect(writes, hasLength(2));
      // An older host must keep seeing exactly the payload it sees today.
      expect(
        gateway.payloadOf(writes.first).containsKey('bracketedPaste'),
        isFalse,
      );
      expect(
        gateway.payloadOf(writes.first).containsKey('deferredEnter'),
        isFalse,
      );
      expect(gateway.payloadOf(writes.last)['bracketedPaste'], isTrue);
      expect(gateway.payloadOf(writes.last)['deferredEnter'], isTrue);
    });

    test(
      'An empty write still reaches the host when the Enter is deferred',
      () async {
        final gateway = await _FakeGateway.start(
          reply: (_) => const <String, Object?>{},
        );
        addTearDown(gateway.dispose);
        final client = await MobileRuntimeClient.connect(gateway.endpoint);
        addTearDown(client.dispose);

        await client.writeTerminal('session-1', const <int>[]);
        expect(gateway.requestsOfType('write'), isEmpty);

        await client.writeTerminal(
          'session-1',
          const <int>[],
          deferredEnter: true,
        );
        expect(gateway.requestsOfType('write'), hasLength(1));
      },
    );
  });

  group('Output resync', () {
    test('Repeated asks produce exactly one resume request', () async {
      final gateway = await _FakeGateway.start(
        reply: (_) => const <String, Object?>{'delta': true, 'resumed': true},
      );
      addTearDown(gateway.dispose);
      final client = await MobileRuntimeClient.connect(gateway.endpoint);
      addTearDown(client.dispose);
      final received = <MobileTerminalOutputEvent>[];
      final outputSub = client.terminalOutput.listen(received.add);
      addTearDown(outputSub.cancel);

      // The host re-arms this ask every few milliseconds until it sees the
      // resume, so the answer has to collapse to one request in flight.
      for (var attempt = 0; attempt < 5; attempt++) {
        gateway.emit('outputResyncRequired', <String, Object?>{
          'sessionId': 'session-1',
        });
      }
      // All five asks are on the wire before any reply can come back, so the
      // resume that does go out is provably still in flight for the other four.
      await _waitUntil(
        () => gateway.requestsOfType('setOutputPaused').isNotEmpty,
      );
      await pumpEventQueue();

      final resumes = gateway.requestsOfType('setOutputPaused');
      expect(resumes, hasLength(1));
      expect(gateway.payloadOf(resumes.single), <String, Object?>{
        'sessionId': 'session-1',
        'paused': false,
      });
      // A delta resume needs nothing locally: the host already pushed the
      // missed bytes down the terminal lane.
      expect(received, isEmpty);
    });

    test('A snapshot answer replaces the scrollback', () async {
      final gateway = await _FakeGateway.start(
        reply: (_) => <String, Object?>{
          'delta': false,
          'snapshotBase64': base64Encode(utf8.encode('restored')),
        },
      );
      addTearDown(gateway.dispose);
      final client = await MobileRuntimeClient.connect(gateway.endpoint);
      addTearDown(client.dispose);
      final received = <MobileTerminalOutputEvent>[];
      final outputSub = client.terminalOutput.listen(received.add);
      addTearDown(outputSub.cancel);

      gateway.emit('outputResyncRequired', <String, Object?>{
        'sessionId': 'session-1',
      });
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single.sessionId, 'session-1');
      expect(received.single.replacesScrollback, isTrue);
      expect(utf8.decode(received.single.data), 'restored');
    });

    test('A later ask for the same session is answered again', () async {
      // A snapshot answer, so each completed resync has an observable effect to
      // wait on: waiting on the request alone would race the socket round trip
      // and could deduplicate the second ask against a still-pending first.
      final gateway = await _FakeGateway.start(
        reply: (_) => <String, Object?>{
          'delta': false,
          'snapshotBase64': base64Encode(utf8.encode('restored')),
        },
      );
      addTearDown(gateway.dispose);
      final client = await MobileRuntimeClient.connect(gateway.endpoint);
      addTearDown(client.dispose);
      final received = <MobileTerminalOutputEvent>[];
      final outputSub = client.terminalOutput.listen(received.add);
      addTearDown(outputSub.cancel);

      gateway.emit('outputResyncRequired', <String, Object?>{
        'sessionId': 'session-1',
      });
      await _waitUntil(() => received.length == 1);
      gateway.emit('outputResyncRequired', <String, Object?>{
        'sessionId': 'session-1',
      });
      await _waitUntil(() => received.length == 2);

      // The in-flight entry is released on completion, so a later pause is
      // recoverable too rather than the client answering only the first one.
      expect(gateway.requestsOfType('setOutputPaused'), hasLength(2));
    });
  });

  test('A closed socket ends both streams', () async {
    final gateway = await _FakeGateway.start(
      reply: (_) => const <String, Object?>{},
    );
    addTearDown(gateway.dispose);
    final client = await MobileRuntimeClient.connect(gateway.endpoint);
    addTearDown(client.dispose);
    var eventsDone = false;
    var outputDone = false;
    final eventsSub = client.events.listen(
      (_) {},
      onDone: () => eventsDone = true,
    );
    final outputSub = client.terminalOutput.listen(
      (_) {},
      onDone: () => outputDone = true,
    );
    addTearDown(eventsSub.cancel);
    addTearDown(outputSub.cancel);

    await gateway.closeSockets();
    await pumpEventQueue();

    // Otherwise a dead socket is indistinguishable from an idle terminal.
    expect(eventsDone, isTrue);
    expect(outputDone, isTrue);
  });
}
