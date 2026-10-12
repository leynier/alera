import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_detail.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_header_card.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_state_strip.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_hosts_settings_pane.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/remote_hosts_widget_harness.dart';

void main() {
  testWidgets('shows one empty state with Add Host when there are no hosts', (
    tester,
  ) async {
    final runtime = FakeRemoteHostsRuntime();
    await pumpRemoteHostsHarness(
      tester,
      runtime,
      const RemoteHostsSettingsPane(),
    );

    expect(find.text('No remote hosts'), findsOneWidget);
    expect(find.text(remoteHostsEmptyMessage), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add Host'), findsOneWidget);
    expect(find.byType(RemoteHostHeaderCard), findsNothing);
  });

  testWidgets('selects the first host and follows a row tap', (tester) async {
    final runtime = FakeRemoteHostsRuntime(
      targets: <Map<String, Object?>>[
        remoteHostTargetJson('mac', 'Build Mac'),
        remoteHostTargetJson('box', 'Linux Box', port: 2222),
      ],
    );
    await pumpRemoteHostsHarness(
      tester,
      runtime,
      const RemoteHostsSettingsPane(),
      projects: <Project>[
        remoteHostTestProject(
          'p1',
          'Alera',
          checkouts: const <ProjectCheckout>[
            ProjectCheckout(hostId: 'box', path: '/srv/alera'),
          ],
        ),
      ],
    );

    expect(_headerText('Build Mac'), findsOneWidget);
    expect(find.text('leynier@mac.local · No projects'), findsOneWidget);
    expect(find.text('leynier@box.local:2222 · 1 project'), findsOneWidget);

    await tester.tap(find.text('Linux Box'));
    await settleRemoteHosts(tester);

    expect(_headerText('Linux Box'), findsOneWidget);
    expect(find.text('Alera'), findsOneWidget);
    expect(find.text('/srv/alera'), findsOneWidget);
  });

  testWidgets('opens on the host the deep link names', (tester) async {
    final runtime = FakeRemoteHostsRuntime(
      targets: <Map<String, Object?>>[
        remoteHostTargetJson('mac', 'Build Mac'),
        remoteHostTargetJson('box', 'Linux Box'),
      ],
    );
    await pumpRemoteHostsHarness(
      tester,
      runtime,
      const RemoteHostsSettingsPane(initialHostId: 'box'),
    );

    expect(_headerText('Linux Box'), findsOneWidget);
    expect(_headerText('Build Mac'), findsNothing);
  });

  testWidgets('a host that needs setup offers Install Runtime', (tester) async {
    final runtime =
        FakeRemoteHostsRuntime(
            targets: <Map<String, Object?>>[
              remoteHostTargetJson(
                'mac',
                'Build Mac',
                bootstrapStatus: 'notInstalled',
              ),
            ],
          )
          ..responses['sshTarget.bootstrap.start'] = <String, Object?>{
            'jobId': 'job-1',
            'targetId': 'mac',
            'status': 'installing',
          };
    await pumpRemoteHostsHarness(
      tester,
      runtime,
      const RemoteHostsSettingsPane(),
    );

    expect(find.text('Needs Setup'), findsWidgets);
    expect(find.text(remoteHostNeedsSetupMessage), findsOneWidget);

    await tester.tap(_primary('Install Runtime'));
    await settleRemoteHosts(tester);

    expect(
      runtime.payloadsOf('sshTarget.bootstrap.start').single,
      <String, Object?>{
        'targetId': 'mac',
        'installDir': null,
        'platform': null,
        'arch': null,
      },
    );
    expect(find.text('Installing Alera runtime on Build Mac'), findsOneWidget);
    expect(find.text('Cancel Install'), findsOneWidget);
    expect(find.text('Authenticate'), findsOneWidget);
  });

  testWidgets('connects a disconnected host and disconnects a connected one', (
    tester,
  ) async {
    final runtime =
        FakeRemoteHostsRuntime(
            targets: <Map<String, Object?>>[
              remoteHostTargetJson('mac', 'Build Mac'),
              remoteHostTargetJson(
                'box',
                'Linux Box',
                hostStatus: <String, Object?>{'state': 'connected'},
              ),
            ],
          )
          ..responses['hostLink.connect'] = <String, Object?>{
            'hostId': 'mac',
            'state': 'connecting',
          }
          ..responses['hostLink.disconnect'] = <String, Object?>{
            'hostId': 'box',
            'state': 'disconnected',
          };
    await pumpRemoteHostsHarness(
      tester,
      runtime,
      const RemoteHostsSettingsPane(),
    );

    expect(find.text('Not Connected'), findsWidgets);
    await tester.tap(_primary('Connect'));
    await settleRemoteHosts(tester);
    expect(runtime.payloadsOf('hostLink.connect').single['hostId'], 'mac');

    await tester.tap(find.text('Linux Box'));
    await settleRemoteHosts(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Disconnect'));
    await settleRemoteHosts(tester);
    expect(runtime.payloadsOf('hostLink.disconnect').single['hostId'], 'box');
  });

  testWidgets('an error offers Retry and Copy Error', (tester) async {
    final runtime = FakeRemoteHostsRuntime(
      targets: <Map<String, Object?>>[
        remoteHostTargetJson(
          'mac',
          'Build Mac',
          hostStatus: <String, Object?>{
            'state': 'error',
            'detail': 'Permission denied (publickey).',
          },
        ),
      ],
    );
    await pumpRemoteHostsHarness(
      tester,
      runtime,
      const RemoteHostsSettingsPane(),
    );

    expect(find.text('Error'), findsWidgets);
    expect(find.text('Permission denied (publickey).'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Copy Error'), findsOneWidget);
  });

  testWidgets('Update Runtime confirms closing terminals on a busy host', (
    tester,
  ) async {
    final runtime =
        FakeRemoteHostsRuntime(
            targets: <Map<String, Object?>>[
              remoteHostTargetJson(
                'mac',
                'Build Mac',
                hostStatus: <String, Object?>{
                  'state': 'connected',
                  'runtimeUpdateAvailable': true,
                  'satelliteVersion': '1.4.0',
                  'hubVersion': '1.5.0',
                },
              ),
            ],
          )
          ..capabilities.add(aleraRuntimeHostRemoteRuntimeUpdateCapability)
          ..errorSequences['sshTarget.bootstrap.start'] = <Object?>[
            const TerminalHostConflictException(
              code: 'hostBusy',
              message: 'busy',
              details: <String, Object?>{
                'hostId': 'mac',
                'alias': 'Build Mac',
                'activeSessions': 2,
              },
            ),
          ]
          ..responses['sshTarget.bootstrap.start'] = <String, Object?>{
            'jobId': 'job-2',
            'targetId': 'mac',
            'status': 'installing',
          };
    await pumpRemoteHostsHarness(
      tester,
      runtime,
      const RemoteHostsSettingsPane(),
    );

    expect(find.text('Update Available'), findsWidgets);
    expect(
      find.text(
        'Alera runtime 1.5.0 is available for this host. The current version is 1.4.0.',
      ),
      findsOneWidget,
    );

    await tester.tap(_primary('Update Runtime').first);
    await settleRemoteHosts(tester);
    expect(find.text('Close 2 Terminals and Update'), findsOneWidget);

    await tester.tap(find.text('Close 2 Terminals and Update'));
    await settleRemoteHosts(tester);

    final starts = runtime.payloadsOf('sshTarget.bootstrap.start');
    expect(starts, hasLength(2));
    expect(starts.first['force'], isFalse);
    expect(starts.last['restartRuntime'], isTrue);
    expect(starts.last['force'], isTrue);
  });

  testWidgets('Remove Host confirms, then forgets the host', (tester) async {
    final runtime = FakeRemoteHostsRuntime(
      targets: <Map<String, Object?>>[remoteHostTargetJson('mac', 'Build Mac')],
    );
    await pumpRemoteHostsHarness(
      tester,
      runtime,
      const RemoteHostsSettingsPane(),
    );

    await _openRemove(tester);
    expect(find.text('Remove Build Mac?'), findsOneWidget);
    expect(
      find.text(
        'Alera forgets this host. The Alera runtime and your files on the host are not deleted.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await settleRemoteHosts(tester);

    expect(runtime.payloadsOf('sshTarget.remove').single['id'], 'mac');
    expect(find.text('No remote hosts'), findsOneWidget);
  });

  testWidgets('Remove Host is disabled while the host is in use', (
    tester,
  ) async {
    final runtime = FakeRemoteHostsRuntime(
      targets: <Map<String, Object?>>[remoteHostTargetJson('mac', 'Build Mac')],
    );
    await pumpRemoteHostsHarness(
      tester,
      runtime,
      const RemoteHostsSettingsPane(),
      projects: <Project>[
        remoteHostTestProject('p1', 'Alera', primaryHostId: 'mac'),
      ],
    );

    await _openRemove(tester);

    expect(find.text('Remove Build Mac?'), findsNothing);
    expect(find.byTooltip(remoteHostInUseRemoveReason), findsOneWidget);
  });

  testWidgets('a refused removal explains what still uses the host', (
    tester,
  ) async {
    final runtime =
        FakeRemoteHostsRuntime(
            targets: <Map<String, Object?>>[
              remoteHostTargetJson('mac', 'Build Mac'),
            ],
          )
          ..errors['sshTarget.remove'] = const TerminalHostConflictException(
            code: 'sshTargetInUse',
            message: 'in use',
            details: <String, Object?>{
              'hostId': 'mac',
              'alias': 'Build Mac',
              'workspaceCount': 2,
              'checkoutCount': 1,
            },
          );
    await pumpRemoteHostsHarness(
      tester,
      runtime,
      const RemoteHostsSettingsPane(),
    );

    await _openRemove(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await settleRemoteHosts(tester);

    expect(
      find.text(
        'Build Mac still has 1 project and 2 workspaces. Remove them first.',
      ),
      findsOneWidget,
    );
    expect(_headerText('Build Mac'), findsOneWidget);
  });
}

Finder _headerText(String text) => find.descendant(
  of: find.byType(RemoteHostHeaderCard),
  matching: find.text(text),
);

Finder _primary(String label) => find.descendant(
  of: find.byType(RemoteHostHeaderCard),
  matching: find.widgetWithText(FilledButton, label),
);

Future<void> _openRemove(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More Actions'));
  await settleRemoteHosts(tester);
  await tester.tap(find.text('Remove Host'));
  await settleRemoteHosts(tester);
}
