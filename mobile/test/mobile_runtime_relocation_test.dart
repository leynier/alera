import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/core/mobile_protocol.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter_test/flutter_test.dart';

Future<(MobileRuntimeClient, List<Map<String, Object?>>)> connect({
  bool capable = true,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final sockets = <WebSocket>[];
  final requests = <Map<String, Object?>>[];
  MobileRuntimeClient? connected;
  var closing = false;
  final subscription = server.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    sockets.add(socket);
    socket.listen((raw) {
      final message = jsonDecode(raw as String) as Map<String, Object?>;
      requests.add(message);
      final type = message['type'];
      final payload = switch (type) {
        'mobile.hello' => {
          'runtimeCapabilities': [
            sharedCheckoutWorkspacesCapability,
            if (capable) 'safeWorkspaceHandoffV1',
          ],
        },
        'workspace.bufferGuard.acquire' => {'guardId': 'guard', 'ready': true},
        'workspace.handOff' || 'workspace.handOn' => {
          'workspace': {
            'id': 'task',
            'projectId': 'project',
            'name': 'Task',
            'path': type == 'workspace.handOff' ? '/linked/task' : '/project',
            'kind': type == 'workspace.handOff' ? 'linked' : 'main',
          },
          'setupReport': {'steps': <Object?>[]},
          if (type == 'workspace.handOff')
            'deferredSetupCommand': 'setup-command',
        },
        _ => <String, Object?>{},
      };
      if (closing || socket.readyState != WebSocket.open) return;
      socket.add(
        jsonEncode({'id': message['id'], 'ok': true, 'payload': payload}),
      );
    });
  });
  addTearDown(() async {
    closing = true;
    await connected?.dispose();
    for (final socket in sockets) {
      await socket.close();
    }
    await subscription.cancel();
    await server.close(force: true);
  });
  final client = await MobileRuntimeClient.connect(
    'ws://${server.address.address}:${server.port}',
  );
  connected = client;
  await client.authenticate(deviceId: 'device', deviceToken: 'token');
  return (client, requests);
}

void main() {
  test('mobile transfers preserve task and operation identity through buffer guards', () async {
    final (client, requests) = await connect();
    const id = '123e4567-e89b-12d3-a456-426614174000';
    final creation = await client.handOffWorkspace(
      workspaceId: 'task',
      relocationId: id,
      branch: 'topic',
      moveChanges: true,
      replacementBranch: 'main',
      sharedImpactConfirmed: true,
    );
    expect(creation.workspace.id, 'task');
    expect(creation.hasDeferredSetup, isTrue);
    final handOff = requests.singleWhere(
      (request) => request['type'] == 'workspace.handOff',
    )['payload'];
    expect(handOff, {
      'id': 'task',
      'relocationId': id,
      'branch': 'topic',
      'moveChanges': true,
      'replacementBranch': 'main',
      'reuseExistingBranch': true,
      'sharedImpactConfirmed': true,
      'deferSetup': true,
      'bufferGuardId': 'guard',
    });
    final returned = await client.handOnWorkspace(
      workspaceId: 'task',
      relocationId: id,
      sharedImpactConfirmed: true,
    );
    expect(returned.id, 'task');
    expect(returned.isMain, isTrue);
    final handOn = requests.singleWhere(
      (request) => request['type'] == 'workspace.handOn',
    )['payload'];
    expect(handOn, {
      'id': 'task',
      'relocationId': id,
      'sharedImpactConfirmed': true,
      'bufferGuardId': 'guard',
    });
    expect(
      requests.where(
        (request) => request['type'] == 'workspace.bufferGuard.release',
      ),
      hasLength(2),
    );
  });

  test('mobile transfers require capability and explicit impact consent before any mutation', () async {
    for (final capable in [false, true]) {
      final (client, requests) = await connect(capable: capable);
      await expectLater(
        client.handOnWorkspace(
          workspaceId: 'task',
          relocationId: 'attempt',
          sharedImpactConfirmed: !capable,
        ),
        throwsA(capable ? isA<StateError>() : isA<UnsupportedError>()),
      );
      expect(
        requests.where(
          (request) => (request['type'] as String).startsWith('workspace.'),
        ),
        isEmpty,
      );
    }
  });
}
