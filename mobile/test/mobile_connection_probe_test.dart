import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Concurrent foreground consumers share one lightweight probe', () async {
    final probeSeen = Completer<void>();
    final release = Completer<void>();
    var probes = 0;
    final client = await _client((message) async {
      if (message['type'] == 'mobile.status.get') {
        probes++;
        expect(message['payload'], {'includeNetworkStatus': false});
        if (!probeSeen.isCompleted) probeSeen.complete();
        await release.future;
      }
    });
    final first = client.probeConnection();
    final second = client.probeConnection();
    expect(second, same(first));
    await probeSeen.future;
    expect(probes, 1);
    release.complete();
    await Future.wait([first, second]);
    expect(client.debugPendingRequestCount, 0);
    await client.probeConnection();
    expect(probes, 2);
  });

  test('Authentication does not wait for optional runtime metadata', () async {
    final metadata = Completer<void>();
    final release = Completer<void>();
    final client = await _client((message) async {
      if (message['type'] == 'status.get') {
        metadata.complete();
        await release.future;
      }
    });
    await client
        .authenticate(deviceId: 'phone', deviceToken: 'token')
        .timeout(const Duration(seconds: 1));
    await metadata.future;
    expect(client.isConnectionUsable, isTrue);
    await client.probeConnection();
    release.complete();
  });
}

Future<MobileRuntimeClient> _client(
  Future<void> Function(Map<String, Object?>) onMessage,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final sockets = <WebSocket>[];
  final subscription = server.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    sockets.add(socket);
    socket.listen((raw) async {
      final message = jsonDecode(raw as String) as Map<String, Object?>;
      await onMessage(message);
      if (socket.readyState == WebSocket.open) {
        socket.add(
          jsonEncode({
            'id': message['id'],
            'ok': true,
            'payload': <String, Object?>{},
          }),
        );
      }
    });
  });
  final client = await MobileRuntimeClient.connect(
    'ws://127.0.0.1:${server.port}',
  );
  addTearDown(() async {
    await client.dispose();
    for (final socket in sockets) {
      await socket.close();
    }
    await subscription.cancel();
    await server.close(force: true);
  });
  return client;
}
