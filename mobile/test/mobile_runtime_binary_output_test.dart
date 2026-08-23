import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runtime stand-in that can accept or decline the binary upgrade.
Future<({HttpServer server, List<Map<String, Object?>> requests})> _runtime({
  required bool grantBinaryFrames,
  required void Function(WebSocket socket) onAuthenticated,
  bool binaryJsonResponses = false,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final requests = <Map<String, Object?>>[];
  final sockets = <WebSocket>[];
  addTearDown(() async {
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
  });
  final subscription = server.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    sockets.add(socket);
    socket.listen((raw) {
      final message = jsonDecode(raw as String) as Map<String, Object?>;
      requests.add(message);
      final response = jsonEncode(<String, Object?>{
        'id': message['id'],
        'ok': true,
        'payload': <String, Object?>{
          'runtimeCapabilities': <String>[
            if (grantBinaryFrames) mobileBinaryFramesCapability,
          ],
          if (grantBinaryFrames) 'binaryFrames': true,
        },
      });
      socket.add(
        binaryJsonResponses && message['type'] != 'mobile.hello'
            ? Uint8List.fromList(utf8.encode(response))
            : response,
      );
      if (message['type'] == 'mobile.hello') {
        onAuthenticated(socket);
      }
    });
  });
  addTearDown(subscription.cancel);
  return (server: server, requests: requests);
}

Uint8List _outputMessage(String sessionId, List<int> data) {
  final id = utf8.encode(sessionId);
  return Uint8List.fromList(<int>[
    (id.length >> 8) & 0xff,
    id.length & 0xff,
    ...id,
    ...data,
  ]);
}

void main() {
  test('asks for binary frames and receives raw output', () async {
    late WebSocket runtimeSocket;
    final runtime = await _runtime(
      grantBinaryFrames: true,
      onAuthenticated: (socket) => runtimeSocket = socket,
    );
    final client = await MobileRuntimeClient.connect(
      'ws://${runtime.server.address.address}:${runtime.server.port}',
    );
    addTearDown(client.dispose);

    await client.authenticate(deviceId: 'device-1', deviceToken: 'token-1');
    expect(
      (runtime.requests.single['payload']! as Map)['binaryFrames'],
      isTrue,
    );

    final output = client.terminalOutput.first;
    // Bytes that are not valid UTF-8, so a JSON round-trip without base64
    // would have destroyed them.
    runtimeSocket.add(_outputMessage('session-1', <int>[0x1b, 0xff, 0x00]));

    final event = await output;
    expect(event.sessionId, 'session-1');
    expect(event.data, <int>[0x1b, 0xff, 0x00]);
  });

  test('a runtime that declines keeps sending base64 in JSON', () async {
    // The compatibility case that is easiest to break, because the phone
    // updates on its own schedule and mobile.hello demands an exact version.
    late WebSocket runtimeSocket;
    final runtime = await _runtime(
      grantBinaryFrames: false,
      onAuthenticated: (socket) => runtimeSocket = socket,
    );
    final client = await MobileRuntimeClient.connect(
      'ws://${runtime.server.address.address}:${runtime.server.port}',
    );
    addTearDown(client.dispose);

    await client.authenticate(deviceId: 'device-1', deviceToken: 'token-1');

    final output = client.terminalOutput.first;
    runtimeSocket.add(
      jsonEncode(<String, Object?>{
        'event': 'output',
        'payload': <String, Object?>{
          'sessionId': 'session-1',
          'dataBase64': base64Encode(<int>[1, 2, 3]),
        },
      }),
    );

    final event = await output;
    expect(event.data, <int>[1, 2, 3]);
  });

  test('binary mode still accepts JSON responses carried as bytes', () async {
    final runtime = await _runtime(
      grantBinaryFrames: true,
      binaryJsonResponses: true,
      onAuthenticated: (_) {},
    );
    final client = await MobileRuntimeClient.connect(
      'ws://${runtime.server.address.address}:${runtime.server.port}',
    );
    addTearDown(client.dispose);
    await client.authenticate(deviceId: 'device-1', deviceToken: 'token-1');

    final response = await client.requestMap('mobile.status.get');

    expect(response['binaryFrames'], isTrue);
  });

  test('a truncated binary message is ignored, not fatal', () async {
    late WebSocket runtimeSocket;
    final runtime = await _runtime(
      grantBinaryFrames: true,
      onAuthenticated: (socket) => runtimeSocket = socket,
    );
    final client = await MobileRuntimeClient.connect(
      'ws://${runtime.server.address.address}:${runtime.server.port}',
    );
    addTearDown(client.dispose);
    await client.authenticate(deviceId: 'device-1', deviceToken: 'token-1');

    final output = client.terminalOutput.first;
    // Claims a 90-byte session id it does not carry.
    runtimeSocket.add(Uint8List.fromList(<int>[0, 90, 0x61]));
    runtimeSocket.add(_outputMessage('session-1', <int>[9]));

    final event = await output.timeout(const Duration(seconds: 5));
    expect(event.data, <int>[9], reason: 'the stream must keep working');
  });
}
