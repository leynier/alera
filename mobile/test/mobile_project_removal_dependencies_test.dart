import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> dependency(String id, {bool requiresPause = true}) => {
  'id': id,
  'name': 'Automation $id',
  'activeRuns': requiresPause ? 1 : 0,
  'requiresPause': requiresPause,
};

Future<MobileRuntimeClient> connectFixture(
  Object? Function(String type, Map<String, Object?> payload) respond,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final sockets = <WebSocket>[];
  final subscription = server.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    sockets.add(socket);
    socket.listen((raw) {
      final message = jsonDecode(raw as String) as Map<String, Object?>;
      if (message['type'] == 'status.get') {
        socket.add(
          jsonEncode({
            'id': message['id'],
            'ok': true,
            'payload': <String, Object?>{},
          }),
        );
        return;
      }
      if (message['type'] == 'mobile.hello') {
        socket.add(
          jsonEncode({
            'id': message['id'],
            'ok': true,
            'payload': {
              'runtimeCapabilities': [sharedCheckoutWorkspacesCapability],
            },
          }),
        );
        return;
      }
      final payload = respond(
        message['type'] as String,
        Map<String, Object?>.from(message['payload'] as Map),
      );
      socket.add(
        jsonEncode({'id': message['id'], 'ok': true, 'payload': payload}),
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
  await client.authenticate(deviceId: 'fixture', deviceToken: 'fixture-token');
  return client;
}

void main() {
  test('Reviewing project dependencies performs no cancellation', () async {
    final requests = <String>[];
    final client = await connectFixture((type, payload) {
      requests.add(type);
      expect(payload['id'], 'empty-project');
      return [dependency('one')];
    });
    final result = await client.projectRemovalDependencies('empty-project');
    expect(result.single.name, 'Automation one');
    expect(result.single.activeRuns, 1);
    expect(result.single.requiresPause, isTrue);
    expect(requests, ['project.removalDependencies']);
  });

  test('Confirmed cancellation waits for the approved runs to stop', () async {
    final requests = <String>[];
    var reads = 0;
    final client = await connectFixture((type, payload) {
      requests.add(type);
      if (type == 'automation.pause') {
        expect(payload['id'], 'one');
        expect(payload['activeRuns'], 'cancel-active');
        return <String, Object?>{};
      }
      expect(type, 'project.removalDependencies');
      expect(payload['id'], 'project');
      reads++;
      return [dependency('one', requiresPause: reads < 3)];
    });
    final approved = await client.projectRemovalDependencies('project');
    await client.pauseProjectRemovalDependencies('project', approved);
    expect(requests, [
      'project.removalDependencies',
      'automation.pause',
      'project.removalDependencies',
      'project.removalDependencies',
    ]);
  });

  test(
    'New dependencies require new confirmation and are not paused',
    () async {
      final paused = <String>[];
      var reads = 0;
      final client = await connectFixture((type, payload) {
        if (type == 'automation.pause') {
          paused.add(payload['id'] as String);
          return <String, Object?>{};
        }
        expect(type, 'project.removalDependencies');
        reads++;
        return reads == 1 ? [dependency('one')] : [dependency('two')];
      });
      final approved = await client.projectRemovalDependencies('project');
      await expectLater(
        client.pauseProjectRemovalDependencies('project', approved),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('confirm their impact again'),
          ),
        ),
      );
      expect(paused, ['one']);
    },
  );
}
