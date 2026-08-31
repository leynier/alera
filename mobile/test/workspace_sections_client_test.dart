import 'dart:convert';
import 'dart:io';

import 'package:alera_mobile/src/features/runtime/infra/mobile_runtime_client.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final supported in [false, true]) {
    test('section preferences respect runtime support ($supported)', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final requests = <Map<String, dynamic>>[];
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
          final message = jsonDecode(raw as String) as Map<String, dynamic>;
          requests.add(message);
          final payload = switch (message['type']) {
            'mobile.hello' => {
              'runtimeCapabilities': [if (supported) 'workspaceSectionsV1'],
            },
            'workbenchViewPrefs.get' || 'workbenchViewPrefs.update' => {
              'revision': 3,
              'prefs': {
                'groupBy': 'section',
                'sectionSort': 'recent',
                'collapsedSectionIds': ['s'],
                'othersSectionCollapsed': true,
              },
            },
            'workspaceSection.list' => <Object?>[],
            _ => <String, Object?>{},
          };
          socket.add(
            jsonEncode({'id': message['id'], 'ok': true, 'payload': payload}),
          );
        });
      });
      addTearDown(subscription.cancel);
      final client = await MobileRuntimeClient.connect(
        'ws://${server.address.address}:${server.port}',
      );
      addTearDown(client.dispose);
      await client.authenticate(deviceId: 'phone', deviceToken: 'test-token');
      expect(client.supportsWorkspaceSections, supported);
      final prefs = await client.loadWorkbenchViewPrefs();
      expect(
        prefs.groupBy,
        supported
            ? MobileWorkspaceGroupBy.section
            : MobileWorkspaceGroupBy.project,
      );
      expect(prefs.sectionSort, MobileWorkbenchSortBy.recent);
      expect(prefs.collapsedSectionIds, {'s'});
      await client.updateWorkbenchViewPrefs(
        prefs.copyWith(groupBy: MobileWorkspaceGroupBy.section),
      );
      final update = requests.lastWhere(
        (request) => request['type'] == 'workbenchViewPrefs.update',
      );
      final shared = update['payload']['prefs'] as Map;
      expect(shared['groupBy'], supported ? 'section' : 'project');
      expect(shared.containsKey('sectionSort'), supported);
      expect(shared.containsKey('collapsedSectionIds'), supported);
      expect(shared.containsKey('othersSectionCollapsed'), supported);
      if (supported) {
        expect(await client.listWorkspaceSections(), isEmpty);
        await client.createWorkspaceSection('Work', 'w');
        await client.setWorkspaceSection('w', null);
        await client.removeWorkspaceSection('s');
        expect(
          requests
              .where(
                (request) =>
                    (request['type'] as String).startsWith('workspaceSection.'),
              )
              .map((request) => request['type']),
          [
            'workspaceSection.list',
            'workspaceSection.create',
            'workspaceSection.setForWorkspace',
            'workspaceSection.remove',
          ],
        );
        expect(
          requests.firstWhere(
            (request) => request['type'] == 'workspaceSection.setForWorkspace',
          )['payload'],
          {'workspaceId': 'w', 'sectionId': null},
        );
      }
    });
  }
}
