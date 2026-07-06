import 'dart:async';

import 'package:alera_mobile/src/alera_mobile_app.dart';
import 'package:alera_mobile/src/models.dart';
import 'package:alera_mobile/src/network/mobile_runtime_client.dart';
import 'package:alera_mobile/src/storage/host_repository.dart';
import 'package:alera_mobile/src/widgets/terminal_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Pairing Result Uses Host Name For Stored Profile', () {
    final profile = PairedHostProfile.fromPairingResult(
      PairingOffer(
        version: aleraMobileProtocolVersion,
        pairingId: 'pairing',
        endpoint: 'ws://127.0.0.1:6768',
        runtimeId: 'runtime',
        hostName: 'Alera Workstation',
        pairingSecret: 'secret',
        expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 10)),
      ),
      const PairedDeviceCredentials(
        deviceId: 'device',
        displayName: 'Alera Mobile',
        runtimeId: 'runtime',
        deviceToken: 'token',
      ),
    );

    expect(profile.displayName, 'Alera Workstation');
  });

  testWidgets('Shows Stored Paired Host', (WidgetTester tester) async {
    final repository = MemoryHostRepository();
    await repository.savePairedHost(
      PairedHostProfile(
        id: 'runtime',
        displayName: 'Alera Dev',
        endpoint: 'ws://127.0.0.1:6768',
        runtimeId: 'runtime',
        deviceId: 'device',
        pairedAt: DateTime.now().toUtc(),
      ),
      'device-token',
    );

    await tester.pumpWidget(AleraMobileApp(hostRepository: repository));
    await tester.pumpAndSettle();

    expect(find.text('Alera Dev'), findsOneWidget);
    expect(await repository.readDeviceToken('runtime'), 'device-token');
  });

  testWidgets('Terminal Preview Creates Fresh Session After Exited Attach', (
    WidgetTester tester,
  ) async {
    final client = _FakeTerminalClient();
    addTearDown(() async {
      await client.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalPreview(
            client: client,
            workspaces: <WorkspaceSummary>[
              WorkspaceSummary(
                id: 'workspace-1',
                projectId: 'project-1',
                name: 'Workspace One',
                path: '/tmp/workspace',
                branch: 'main',
              ),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pump();

    expect(
      client.requests,
      containsAllInOrder(<String>[
        'tab.list',
        'terminal.attach',
        'detach',
        'terminal.create',
      ]),
    );
    expect(find.text('Attached'), findsOneWidget);
  });
}

class _FakeTerminalClient implements MobileTerminalClient {
  final StreamController<MobileTerminalOutputEvent> _output =
      StreamController<MobileTerminalOutputEvent>.broadcast();
  final List<String> requests = <String>[];

  @override
  Stream<MobileTerminalOutputEvent> get terminalOutput => _output.stream;

  @override
  Future<List<WorkspaceTabSummary>> listTabs(String workspaceId) async {
    requests.add('tab.list');
    return <WorkspaceTabSummary>[_tab(id: 'tab-1', workspaceId: workspaceId)];
  }

  @override
  Future<MobileTerminalSession> attachTerminal(String tabId) async {
    requests.add('terminal.attach');
    return _session(tabId: tabId, sessionId: 'exited-session', running: false);
  }

  @override
  Future<void> detachTerminal(String sessionId) async {
    requests.add('detach');
  }

  @override
  Future<MobileTerminalSession> createTerminal(String workspaceId) async {
    requests.add('terminal.create');
    return _session(
      tabId: 'tab-2',
      sessionId: 'running-session',
      workspaceId: workspaceId,
      running: true,
      created: true,
    );
  }

  @override
  Future<void> writeTerminal(String sessionId, List<int> bytes) async {
    requests.add('write');
  }

  Future<void> dispose() async {
    await _output.close();
  }
}

MobileTerminalSession _session({
  required String tabId,
  required String sessionId,
  required bool running,
  String workspaceId = 'workspace-1',
  bool created = false,
}) {
  return MobileTerminalSession(
    tab: _tab(id: tabId, workspaceId: workspaceId),
    attachment: MobileTerminalAttachment(
      sessionId: sessionId,
      created: created,
      running: running,
      snapshot: const <int>[],
    ),
  );
}

WorkspaceTabSummary _tab({required String id, required String workspaceId}) {
  return WorkspaceTabSummary(
    id: id,
    workspaceId: workspaceId,
    kind: 'terminal',
    title: 'Terminal',
    payload: const <String, Object?>{},
  );
}
