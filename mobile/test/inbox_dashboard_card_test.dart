import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/runtime/application/host_dashboard_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_runtime_status.dart';
import 'package:alera_mobile/src/features/runtime/presentation/host_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final PairedHostProfile _host = PairedHostProfile(
  id: 'host',
  displayName: 'Desk',
  endpoint: 'ws://localhost:1',
  runtimeId: 'runtime',
  deviceId: 'phone',
  pairedAt: .utc(2026),
);

class _Hosts extends PairedHostsController {
  @override
  Future<List<PairedHostProfile>> build() async => <PairedHostProfile>[_host];
}

Widget _dashboard({required bool supportsInbox}) => ProviderScope(
  overrides: [
    pairedHostsControllerProvider.overrideWith(_Hosts.new),
    hostDashboardDataProvider('host').overrideWith(
      (ref) async => HostDashboardData(
        status: const MobileRuntimeStatus(
          protocolVersion: 1,
          devices: [],
          activePairings: [],
        ),
        projects: const [],
        workspaces: const [],
        branchesByProject: const {},
        supportsInbox: supportsInbox,
      ),
    ),
  ],
  child: MaterialApp(home: HostDashboardScreen(host: _host)),
);

void main() {
  testWidgets('the dashboard offers the inbox when the host has it', (
    tester,
  ) async {
    await tester.pumpWidget(_dashboard(supportsInbox: true));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byTooltip('Open Inbox'), 200);
    expect(find.byTooltip('Open Inbox'), findsOneWidget);
  });

  testWidgets('the dashboard hides the inbox on an older host', (tester) async {
    await tester.pumpWidget(_dashboard(supportsInbox: false));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byTooltip('Open Automations'), 200);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Open Automations'), findsOneWidget);
    expect(find.byTooltip('Open Inbox'), findsNothing);
  });
}
