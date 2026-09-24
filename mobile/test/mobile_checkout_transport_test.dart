import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  test('SSH branch queries reject unscoped legacy replies and never substitute local data', () async {
    var reply = <String, Object?>{
      'projectId': 'project',
      'branches': ['local-only'],
      'localBranches': ['local-only'],
    };
    final requests = <Map<String, Object?>>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    final subscription = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((raw) {
        final message = jsonDecode(raw as String) as Map<String, Object?>;
        requests.add(message);
        socket.add(
          jsonEncode({'id': message['id'], 'ok': true, 'payload': reply}),
        );
      });
    });
    addTearDown(() async {
      await subscription.cancel();
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    });
    final channel = WebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:${server.port}'),
    );
    await channel.ready;
    final client = MobileRuntimeClient.forTesting(channel);
    addTearDown(client.dispose);
    await expectLater(
      client.listBranches('project', checkoutHostId: 'ssh-box'),
      throwsStateError,
    );
    expect(requests.single['type'], 'project.branches.list');
    expect(requests.single['payload'], {
      'projectId': 'project',
      'hostId': 'ssh-box',
    });
    reply = {
      'projectId': 'project',
      'hostId': 'ssh-box',
      'branches': ['remote-only'],
      'localBranches': ['remote-only'],
    };
    expect(
      (await client.listBranches(
        'project',
        checkoutHostId: 'ssh-box',
      )).branches,
      ['remote-only'],
    );
    expect(requests, hasLength(2));
  });
}
