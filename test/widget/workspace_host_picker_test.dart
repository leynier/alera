import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/workbench/presentation/workspace_host_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/remote_host_view_fixtures.dart';

void main() {
  testWidgets('without hosts it offers Add Host', (tester) async {
    var added = 0;
    await _pump(
      tester,
      hosts: const <RemoteHostView>[],
      onAddHost: () => added++,
    );

    expect(find.text(workspaceHostNoHostsMessage), findsOneWidget);
    await tester.tap(find.text('Add Host'));
    expect(added, 1);
  });

  testWidgets('hosts that are not ready are disabled with the reason', (
    tester,
  ) async {
    await _pump(
      tester,
      hosts: [
        remoteHostView('ok', 'Build Mac', status: const RemoteHostConnected()),
        remoteHostView('off', 'Office', status: const RemoteHostOffline()),
        remoteHostView('new', 'New Box', status: const RemoteHostNeedsSetup()),
        remoteHostView('inst', 'GPU Rig', status: const RemoteHostInstalling()),
        remoteHostView(
          'bad',
          'Old Mac',
          status: const RemoteHostError(detail: 'Denied'),
        ),
      ],
    );

    final entries = {
      for (final entry in _entries(tester)) entry.label: entry.enabled,
    };
    expect(entries, <String, bool>{
      'This Device': true,
      'Build Mac': true,
      'Office': true,
      'New Box (Needs Setup)': false,
      'GPU Rig (Installing…)': false,
      'Old Mac (Error)': false,
    });
  });

  testWidgets('a remote-only project cannot pick This Device', (tester) async {
    await _pump(
      tester,
      hostId: 'ok',
      remoteOnlyProject: true,
      hosts: [remoteHostView('ok', 'Build Mac')],
    );

    expect(_entries(tester).first.enabled, isFalse);
    expect(find.text(workspaceHostNoHostsMessage), findsNothing);
  });

  testWidgets('an offline selection warns and links to the host', (
    tester,
  ) async {
    String? opened;
    await _pump(
      tester,
      hostId: 'off',
      hosts: [
        remoteHostView('off', 'Office', status: const RemoteHostOffline()),
      ],
      onOpenHost: (hostId) => opened = hostId,
    );

    expect(find.text(workspaceHostOfflineMessage('Office')), findsOneWidget);
    await tester.tap(find.text('Open Host'));
    expect(opened, 'off');
  });

  testWidgets('a selection that is not ready explains why', (tester) async {
    await _pump(
      tester,
      hostId: 'new',
      hosts: [
        remoteHostView('new', 'New Box', status: const RemoteHostNeedsSetup()),
      ],
      onOpenHost: (_) {},
    );

    expect(
      find.text('The Alera runtime is not installed on New Box yet.'),
      findsOneWidget,
    );
    expect(find.text('Open Host'), findsOneWidget);
  });

  testWidgets('a runtime without remote workspaces disables every host', (
    tester,
  ) async {
    await _pump(
      tester,
      supported: false,
      hosts: [remoteHostView('ok', 'Build Mac')],
    );

    expect(_entries(tester).last.enabled, isFalse);
    expect(find.textContaining('cannot create remote workspaces'), findsOne);
  });
}

List<AleraDropdownFieldEntry<String?>> _entries(WidgetTester tester) {
  return tester
      .widget<AleraDropdownField<String?>>(
        find.byType(AleraDropdownField<String?>),
      )
      .entries;
}

Future<void> _pump(
  WidgetTester tester, {
  required List<RemoteHostView> hosts,
  String? hostId,
  bool remoteOnlyProject = false,
  bool supported = true,
  VoidCallback? onAddHost,
  ValueChanged<String>? onOpenHost,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildAleraDarkTheme(),
      home: Scaffold(
        body: WorkspaceHostPicker(
          hostId: hostId,
          hosts: hosts,
          remoteOnlyProject: remoteOnlyProject,
          supportsRemoteSshWorkspaces: supported,
          onChanged: (_) {},
          onAddHost: onAddHost,
          onOpenHost: onOpenHost,
        ),
      ),
    ),
  );
}
