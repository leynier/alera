import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/features/remote_hosts/domain/host_link.dart';
import 'package:alera/src/features/settings/presentation/panes/remote_host_link_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpGroup(
  WidgetTester tester, {
  required HostLinkState? state,
  bool busy = false,
  VoidCallback? onConnect,
  VoidCallback? onDisconnect,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: buildAleraDarkTheme(),
      home: Scaffold(
        body: RemoteHostLinkGroup(
          state: state,
          busy: busy,
          onConnect: onConnect,
          onDisconnect: onDisconnect,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('an unknown host offers Connect', (tester) async {
    var connected = 0;
    await pumpGroup(tester, state: null, onConnect: () => connected++);
    expect(find.text('Not connected'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Connect'));
    expect(connected, 1);
    expect(find.widgetWithText(OutlinedButton, 'Disconnect'), findsNothing);
  });

  testWidgets('an attached host shows the satellite and offers Disconnect', (
    tester,
  ) async {
    var disconnected = 0;
    await pumpGroup(
      tester,
      state: const HostLinkState(
        hostId: 'lab',
        phase: HostLinkPhase.attached,
        attachment: HostLinkAttachment(
          runtimeDir: '/data',
          platform: 'macos',
          arch: 'aarch64',
          hostVersion: '1.4.0',
        ),
      ),
      onDisconnect: () => disconnected++,
    );
    expect(find.text('Attached'), findsOneWidget);
    expect(find.textContaining('1.4.0 on macos/aarch64'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Disconnect'));
    expect(disconnected, 1);
  });

  testWidgets('a failed link shows its error and stays connectable', (
    tester,
  ) async {
    await pumpGroup(
      tester,
      state: const HostLinkState(
        hostId: 'lab',
        phase: HostLinkPhase.failed,
        error: 'Permission denied (publickey).',
      ),
      onConnect: () {},
    );
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Permission denied (publickey).'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Connect'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets('connecting disables the button', (tester) async {
    await pumpGroup(
      tester,
      state: const HostLinkState(
        hostId: 'lab',
        phase: HostLinkPhase.connecting,
      ),
      onConnect: () {},
    );
    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Connect'),
    );
    expect(button.onPressed, isNull);
  });
}
