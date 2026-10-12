import 'dart:async';

import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_controller.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/remote_hosts/presentation/add_remote_host_dialog.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/features/workbench/presentation/workbench_dialog_launchers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/remote_hosts_widget_harness.dart';

void main() {
  testWidgets('walks Connection, Install Runtime and Done', (tester) async {
    final runtime = _runtime()
      ..checkPatch = <String, Object?>{'lastStatus': 'reachable'};
    final flow = await _openAddHost(tester, runtime);

    expect(find.text('Connection'), findsWidgets);
    expect(find.text('Install Runtime'), findsOneWidget);
    await _enterField(tester, 'SSH Address', 'leynier@mac.local');
    expect(_fieldText(tester, 'Alias'), 'mac.local');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await settleRemoteHosts(tester);

    final upsert = runtime.payloadsOf('sshTarget.upsert').single;
    expect(upsert['alias'], 'mac.local');
    expect(upsert['host'], 'mac.local');
    expect(upsert['username'], 'leynier');
    expect(upsert['authKind'], 'agent');
    expect(runtime.payloadsOf('sshTarget.check'), hasLength(1));
    expect(find.text('Reached mac.local as leynier'), findsOneWidget);
    expect(find.text('No Alera runtime installed'), findsOneWidget);
    expect(
      find.text('Signed release archive from GitHub Releases'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Install Runtime'));
    await settleRemoteHosts(tester);
    expect(runtime.payloadsOf('sshTarget.bootstrap.start'), hasLength(1));
    expect(find.text('Installing Alera runtime on mac.local'), findsOneWidget);

    final hostId = upsert['id']! as String;
    runtime.emitProgress(hostId, 'upload');
    await settleRemoteHosts(tester);
    expect(find.text('Upload runtime'), findsOneWidget);

    runtime.emitProgress(hostId, 'installed', status: 'installed');
    await settleRemoteHosts(tester);
    expect(find.text('mac.local is ready'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await settleRemoteHosts(tester);
    expect(await flow, hostId);
    expect(find.byType(AddRemoteHostDialog), findsNothing);
  });

  testWidgets('rejects an address without a username before saving', (
    tester,
  ) async {
    final runtime = _runtime();
    await _openAddHost(tester, runtime);

    await _enterField(tester, 'SSH Address', 'mac.local');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await settleRemoteHosts(tester);

    expect(find.text('Include the username, as in user@host.'), findsOneWidget);
    expect(runtime.payloadsOf('sshTarget.upsert'), isEmpty);
  });

  testWidgets('a failed check blocks the install and offers Retry and Back', (
    tester,
  ) async {
    final runtime = _runtime()
      ..checkPatch = <String, Object?>{
        'lastStatus': 'unreachable',
        'lastError':
            'ssh: connect to host mac.local port 22: Connection refused',
      };
    await _openAddHost(tester, runtime);
    await _enterField(tester, 'SSH Address', 'leynier@mac.local');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await settleRemoteHosts(tester);

    expect(
      find.text('ssh: connect to host mac.local port 22: Connection refused'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Install Runtime'),
          )
          .onPressed,
      isNull,
    );

    runtime.checkPatch = <String, Object?>{'lastStatus': 'reachable'};
    await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
    await settleRemoteHosts(tester);
    expect(runtime.payloadsOf('sshTarget.check'), hasLength(2));
    expect(find.text('Reached mac.local as leynier'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Back'));
    await settleRemoteHosts(tester);
    expect(_fieldText(tester, 'SSH Address'), 'leynier@mac.local');
  });

  testWidgets('Close leaves a running install going', (tester) async {
    final runtime = _runtime()
      ..checkPatch = <String, Object?>{'lastStatus': 'reachable'};
    final flow = await _openAddHost(tester, runtime);
    await _enterField(tester, 'SSH Address', 'leynier@mac.local');
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await settleRemoteHosts(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Install Runtime'));
    await settleRemoteHosts(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AddRemoteHostDialog)),
    );
    final hostId =
        runtime.payloadsOf('sshTarget.upsert').single['id']! as String;
    expect(
      container.read(remoteHostsControllerProvider).isInstallDialogOpen(hostId),
      isTrue,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Close'));
    await settleRemoteHosts(tester);

    expect(await flow, hostId);
    expect(find.byType(AddRemoteHostDialog), findsNothing);
    expect(runtime.payloadsOf('sshTarget.bootstrap.cancel'), isEmpty);
    final state = container.read(remoteHostsControllerProvider);
    expect(state.hostById(hostId)!.status, isA<RemoteHostInstalling>());
    expect(state.isInstallDialogOpen(hostId), isFalse);
  });
}

FakeRemoteHostsRuntime _runtime() {
  return FakeRemoteHostsRuntime()
    ..capabilities.add(aleraRuntimeHostRemoteHostStatusCapability)
    ..responses['sshTarget.bootstrap.plan'] = <String, Object?>{
      'targetId': 'any',
      'platform': 'auto',
      'arch': 'auto',
      'installDir': '~/.alera',
      'channel': 'stable',
      'artifactSource': 'githubRelease',
      'trust': 'signedArchive',
      'steps': <Object?>[],
    }
    ..responses['sshTarget.bootstrap.start'] = <String, Object?>{
      'jobId': 'job-1',
      'targetId': 'any',
      'status': 'installing',
    };
}

/// Opens Add Host through its launcher and answers what the flow returned.
Future<Future<String?>> _openAddHost(
  WidgetTester tester,
  FakeRemoteHostsRuntime runtime,
) async {
  final result = Completer<String?>();
  await pumpRemoteHostsHarness(
    tester,
    runtime,
    Consumer(
      builder: (context, ref, _) => Center(
        child: TextButton(
          onPressed: () => unawaited(
            showAddRemoteHostFlow(context, ref).then(result.complete),
          ),
          child: const Text('Open Add Host'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open Add Host'));
  await settleRemoteHosts(tester);
  return result.future;
}

Finder _field(String label) => find.descendant(
  of: find.byWidgetPredicate(
    (widget) => widget is AleraTextField && widget.labelText == label,
  ),
  matching: find.byType(TextField),
);

Future<void> _enterField(
  WidgetTester tester,
  String label,
  String value,
) async {
  await tester.enterText(_field(label), value);
  await tester.pump();
}

String? _fieldText(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller?.text;
