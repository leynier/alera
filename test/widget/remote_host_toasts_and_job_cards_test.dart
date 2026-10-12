import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/remote_hosts/application/remote_host_link_toasts.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_controller.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_visible_host.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_install_steps.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_install_job_cards.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_link_toast_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/remote_host_view_fixtures.dart';
import '../support/remote_hosts_widget_harness.dart';

void main() {
  group('install completion toasts', () {
    RemoteHostsState state(
      SshBootstrapStatus status, {
      Set<String> dialogs = const <String>{},
      bool restart = false,
    }) {
      return RemoteHostsState(
        loading: false,
        installDialogHostIds: dialogs,
        hosts: [
          remoteHostView(
            'mac',
            'Build Mac',
            installProgress: RemoteHostInstallProgress(
              targetId: 'mac',
              jobId: 'job-1',
              status: status,
              includesRestart: restart,
            ),
          ),
        ],
      );
    }

    test('an install that finished out of sight is announced', () {
      final toasts = remoteHostInstallCompletionToasts(
        state(SshBootstrapStatus.installing),
        state(SshBootstrapStatus.installed),
      );
      expect(toasts.single.message, 'Alera runtime installed on Build Mac');
      expect(toasts.single.tone, RemoteHostToastTone.success);
    });

    test('an update says updated', () {
      final toasts = remoteHostInstallCompletionToasts(
        state(SshBootstrapStatus.installing, restart: true),
        state(SshBootstrapStatus.installed, restart: true),
      );
      expect(toasts.single.message, 'Alera runtime updated on Build Mac');
    });

    test('the dialog announces its own install', () {
      expect(
        remoteHostInstallCompletionToasts(
          state(SshBootstrapStatus.installing, dialogs: {'mac'}),
          state(SshBootstrapStatus.installed, dialogs: {'mac'}),
        ),
        isEmpty,
      );
      expect(
        remoteHostInstallCompletionToasts(
          state(SshBootstrapStatus.installed),
          state(SshBootstrapStatus.installed),
        ),
        isEmpty,
      );
    });
  });

  testWidgets('a running and then failed install shows a job card', (
    tester,
  ) async {
    final runtime = FakeRemoteHostsRuntime(
      targets: <Map<String, Object?>>[
        remoteHostTargetJson('mac', 'Build Mac', bootstrapStatus: 'installing'),
      ],
    );
    final container = await pumpRemoteHostsHarness(
      tester,
      runtime,
      const Align(
        alignment: Alignment.bottomRight,
        child: RemoteHostInstallJobCards(),
      ),
    );

    runtime.emitProgress('mac', 'upload');
    await settleRemoteHosts(tester);
    expect(find.text('Installing Alera runtime on Build Mac'), findsOneWidget);
    expect(find.text('Upload runtime'), findsOneWidget);

    final controller = container.read(remoteHostsControllerProvider.notifier);
    controller.setInstallDialogOpen('mac', open: true);
    await settleRemoteHosts(tester);
    expect(find.text('Installing Alera runtime on Build Mac'), findsNothing);

    controller.setInstallDialogOpen('mac', open: false);
    runtime.emitProgress('mac', 'upload', status: 'failed', error: 'Disk full');
    await settleRemoteHosts(tester);
    expect(
      find.text('Could not install the Alera runtime on Build Mac'),
      findsOneWidget,
    );
    expect(find.text('Disk full'), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await settleRemoteHosts(tester);
    expect(
      find.text('Could not install the Alera runtime on Build Mac'),
      findsNothing,
    );
  });

  testWidgets('a dropped link toasts unless its host is on screen', (
    tester,
  ) async {
    final toasts = <AleraToastData>[];
    final subscription = AleraToast.stream.listen(toasts.add);
    addTearDown(subscription.cancel);
    final runtime = FakeRemoteHostsRuntime(
      targets: <Map<String, Object?>>[
        remoteHostTargetJson(
          'mac',
          'Build Mac',
          hostStatus: <String, Object?>{'state': 'connected'},
        ),
        remoteHostTargetJson(
          'box',
          'Linux Box',
          hostStatus: <String, Object?>{'state': 'connected'},
        ),
      ],
    );
    final container = await pumpRemoteHostsHarness(
      tester,
      runtime,
      const _ToastListenerHost(),
    );
    container.read(remoteHostsVisibleHostProvider.notifier).show('box');

    for (final target in runtime.targets) {
      target['hostStatus'] = <String, Object?>{'state': 'offline'};
    }
    runtime.emitTargetsChanged();
    await settleRemoteHosts(tester);

    expect(toasts.map((toast) => toast.message), ['Build Mac disconnected.']);
    expect(toasts.single.actionLabel, remoteHostOpenHostActionLabel);
    expect(
      container.read(remoteHostsControllerProvider).hostById('mac')?.status,
      isA<RemoteHostOffline>(),
    );
  });
}

class const _ToastListenerHost() extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ToastListenerHost> createState() => _ToastListenerHostState();
}

class _ToastListenerHostState extends ConsumerState<_ToastListenerHost> {
  final RemoteHostLinkToastPolicy _policy = RemoteHostLinkToastPolicy();

  @override
  Widget build(BuildContext context) {
    listenRemoteHostLinkToasts(ref, _policy);
    ref.watch(remoteHostsControllerProvider);
    return const SizedBox.shrink();
  }
}
