import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:flutter_test/flutter_test.dart';

Future<(MobileRuntimeClient, List<Map<String, Object?>>)> _connect(
  List<String> capabilities,
) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final sockets = <WebSocket>[];
  final requests = <Map<String, Object?>>[];
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
      socket.add(
        jsonEncode(<String, Object?>{
          'id': message['id'],
          'ok': true,
          'payload': switch (message['type']) {
            'mobile.hello' => <String, Object?>{
              'runtimeCapabilities': capabilities,
            },
            'mobile.workspaceSearch.run' => <String, Object?>{
              'files': <Object?>[],
              'totalMatches': 0,
              'truncated': false,
            },
            'mobile.workspaceSearch.replace' => <String, Object?>{
              'filesChanged': 1,
              'matchesReplaced': 2,
              'conflicts': <Object?>[],
            },
            _ => <String, Object?>{},
          },
        }),
      );
    });
  });
  addTearDown(subscription.cancel);
  final client = await MobileRuntimeClient.connect(
    'ws://${server.address.address}:${server.port}',
  );
  addTearDown(client.dispose);
  await client.authenticate(deviceId: 'device-1', deviceToken: 'token-1');
  return (client, requests);
}

Map<String, Object?> _lastPayload(
  List<Map<String, Object?>> requests,
  String type,
) =>
    requests.lastWhere((request) => request['type'] == type)['payload']!
        as Map<String, Object?>;

void main() {
  test('sends replace, preview, and cancel to a capable host', () async {
    final (client, requests) = await _connect(<String>[
      mobileWorkspaceSearchCapability,
      mobileWorkspaceReplaceCapability,
    ]);
    expect(client.supportsWorkspaceReplace, isTrue);

    await client.searchWorkspace(
      workspaceId: 'ws-1',
      query: 'foo',
      replacement: 'bar',
      preserveCase: true,
      requestId: 'ws-1:1',
    );
    final search = _lastPayload(requests, 'mobile.workspaceSearch.run');
    expect(search['replacement'], 'bar');
    expect(search['preserveCase'], isTrue);
    expect(search['requestId'], 'ws-1:1');

    final result = await client.replaceWorkspaceMatches(
      workspaceId: 'ws-1',
      search: const MobileWorkspaceSearchQuery(
        query: 'foo',
        includePattern: ' lib/** ',
        includeIgnored: true,
      ),
      replacement: 'bar',
      matchIds: const <String>['a.dart:1:1:0'],
      expectedFiles: const <MobileWorkspaceSearchFile>[
        MobileWorkspaceSearchFile(relativePath: 'a.dart', contentToken: '1:2'),
      ],
    );
    expect(result.matchesReplaced, 2);
    final replace = _lastPayload(requests, 'mobile.workspaceSearch.replace');
    expect(replace['query'], 'foo');
    expect(replace['includePattern'], 'lib/**');
    expect(replace['includeIgnored'], isTrue);
    expect(replace['matchIds'], <Object?>['a.dart:1:1:0']);
    expect(replace['expectedFiles'], <Object?>[
      <String, Object?>{'relativePath': 'a.dart', 'contentToken': '1:2'},
    ]);

    await client.cancelWorkspaceSearch('ws-1:1');
    expect(
      _lastPayload(requests, 'mobile.workspaceSearch.cancel')['requestId'],
      'ws-1:1',
    );
  });

  test('an older host gets the plain search and no replace verbs', () async {
    final (client, requests) = await _connect(<String>[
      mobileWorkspaceSearchCapability,
    ]);
    expect(client.supportsWorkspaceReplace, isFalse);

    await client.searchWorkspace(
      workspaceId: 'ws-1',
      query: 'foo',
      replacement: 'bar',
      requestId: 'ws-1:1',
    );
    final search = _lastPayload(requests, 'mobile.workspaceSearch.run');
    expect(search.containsKey('replacement'), isFalse);
    expect(search.containsKey('requestId'), isFalse);

    await client.cancelWorkspaceSearch('ws-1:1');
    expect(
      requests.where((r) => r['type'] == 'mobile.workspaceSearch.cancel'),
      isEmpty,
    );
    await expectLater(
      client.replaceWorkspaceMatches(
        workspaceId: 'ws-1',
        search: const MobileWorkspaceSearchQuery(query: 'foo'),
        replacement: 'bar',
        matchIds: const <String>[],
        expectedFiles: const <MobileWorkspaceSearchFile>[],
      ),
      throwsA(isA<UnsupportedError>()),
    );
  });
}
