import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Requests deferred setup and parses the returned command', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    final requestCompleter = Completer<Map<String, Object?>>();
    final subscription = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((raw) {
        final message = jsonDecode(raw as String) as Map<String, Object?>;
        requestCompleter.complete(message);
        socket.add(
          jsonEncode(<String, Object?>{
            'id': message['id'],
            'ok': true,
            'payload': <String, Object?>{
              'workspace': <String, Object?>{
                'id': 'workspace-1',
                'projectId': 'project-1',
                'name': 'Feature',
                'path': '/workspaces/feature',
              },
              'setupReport': <String, Object?>{'steps': <Object?>[]},
              'deferredSetupCommand': '/bin/sh "/runtime/setup.sh"',
            },
          }),
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
    final client = await MobileRuntimeClient.connect(
      'ws://${server.address.address}:${server.port}',
    );
    addTearDown(client.dispose);

    final result = await client.createManagedWorkspace(
      projectId: 'project-1',
      branch: 'feature/setup',
      sourceBranch: 'main',
    );
    final request = await requestCompleter.future;

    expect(request['type'], 'workspace.createManaged');
    expect(request['payload'], containsPair('deferSetup', true));
    expect(result.deferredSetupCommand, '/bin/sh "/runtime/setup.sh"');
  });
}
