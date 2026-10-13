import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_hosts_status_bar_control.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_hosts_status_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/remote_host_view_fixtures.dart';
import '../support/remote_hosts_widget_harness.dart';

void main() {
  group('chip summary', () {
    test('counts connected hosts and notes an install', () {
      expect(
        remoteHostsChipLabel([
          remoteHostView('a', 'A', status: const RemoteHostConnected()),
          remoteHostView('b', 'B'),
          remoteHostView('c', 'C', status: const RemoteHostOffline()),
        ]),
        'Hosts 1/3',
      );
      expect(
        remoteHostsChipLabel([
          remoteHostView('a', 'A', status: const RemoteHostInstalling()),
        ]),
        'Hosts 0/1 · Installing…',
      );
    });

    test('quick actions follow the state and the runtime', () {
      const full = RemoteHostCapabilities(hostLinks: true, runtimeUpdate: true);
      const none = RemoteHostCapabilities();
      RemoteHostQuickAction? action(
        RemoteHostStatus status, [
        RemoteHostCapabilities capabilities = full,
      ]) => remoteHostQuickAction(
        remoteHostView('a', 'A', status: status),
        capabilities,
      );

      expect(
        action(const RemoteHostDisconnected()),
        RemoteHostQuickAction.connect,
      );
      expect(action(const RemoteHostOffline()), RemoteHostQuickAction.connect);
      expect(action(const RemoteHostOffline(), none), isNull);
      expect(
        action(const RemoteHostError(detail: 'x')),
        RemoteHostQuickAction.retry,
      );
      expect(
        action(const RemoteHostError(detail: 'x', origin: .install), none),
        RemoteHostQuickAction.retry,
      );
      expect(
        action(const RemoteHostConnected(updateAvailable: true)),
        RemoteHostQuickAction.update,
      );
      expect(action(const RemoteHostConnected()), isNull);
      expect(action(const RemoteHostNeedsSetup()), isNull);
      expect(action(const RemoteHostInstalling()), isNull);
    });
  });

  testWidgets('the control stays hidden until a host exists', (tester) async {
    await pumpRemoteHostsHarness(
      tester,
      FakeRemoteHostsRuntime(),
      const Align(
        alignment: Alignment.bottomRight,
        child: RemoteHostsStatusBarControl(),
      ),
    );

    expect(find.byType(RemoteHostsStatusChip), findsNothing);
  });

  testWidgets('the card lists every host with its quick fix', (tester) async {
    final runtime =
        FakeRemoteHostsRuntime(
            targets: <Map<String, Object?>>[
              remoteHostTargetJson(
                'mac',
                'Build Mac',
                hostStatus: <String, Object?>{'state': 'connected'},
              ),
              remoteHostTargetJson(
                'box',
                'Linux Box',
                hostStatus: <String, Object?>{'state': 'offline'},
              ),
              remoteHostTargetJson(
                'rig',
                'GPU Rig',
                bootstrapStatus: 'notInstalled',
                hostStatus: <String, Object?>{'state': 'needsSetup'},
              ),
            ],
          )
          ..responses['hostLink.connect'] = <String, Object?>{
            'hostId': 'box',
            'state': 'connecting',
          };
    await pumpRemoteHostsHarness(
      tester,
      runtime,
      const Align(
        alignment: Alignment.bottomRight,
        child: RemoteHostsStatusBarControl(),
      ),
    );

    expect(find.text('Hosts 1/3'), findsOneWidget);
    await tester.tap(find.text('Hosts 1/3'));
    await settleRemoteHosts(tester);

    expect(find.text('Build Mac'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Needs Setup'), findsOneWidget);
    expect(find.text('Open Remote Hosts'), findsOneWidget);
    expect(find.text('Add Host'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Connect'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Connect'));
    await settleRemoteHosts(tester);
    expect(runtime.payloadsOf('hostLink.connect').single['hostId'], 'box');
  });

  testWidgets('an install shows on the chip', (tester) async {
    final runtime = FakeRemoteHostsRuntime(
      targets: <Map<String, Object?>>[
        remoteHostTargetJson(
          'mac',
          'Build Mac',
          bootstrapStatus: 'installing',
          hostStatus: <String, Object?>{'state': 'installing'},
        ),
      ],
    );
    await pumpRemoteHostsHarness(
      tester,
      runtime,
      const Align(
        alignment: Alignment.bottomRight,
        child: RemoteHostsStatusBarControl(),
      ),
    );

    expect(find.text('Hosts 0/1 · Installing…'), findsOneWidget);
  });
}
