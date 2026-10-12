import 'package:alera_mobile/src/features/hosts/application/paired_hosts_controller.dart';
import 'package:alera_mobile/src/features/hosts/domain/paired_host_profile.dart';
import 'package:alera_mobile/src/features/inbox/application/mobile_inbox_providers.dart';
import 'package:alera_mobile/src/features/runs/application/activity_providers.dart';
import 'package:alera_mobile/src/features/runs/application/mobile_run_providers.dart';
import 'package:alera_mobile/src/features/runs/domain/activity_section.dart';
import 'package:alera_mobile/src/features/runs/presentation/activity_screen.dart';
import 'package:alera_mobile/src/features/runtime/application/host_dashboard_controller.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_runtime_status.dart';
import 'package:alera_mobile/src/features/runtime/presentation/host_dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_inbox_client.dart';
import 'support/fake_runs_client.dart';

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

Widget _dashboard({
  required bool supportsInbox,
  required bool supportsRuns,
  FakeRunsClient? runs,
  FakeInboxClient? inbox,
}) => ProviderScope(
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
        supportsRuns: supportsRuns,
      ),
    ),
    mobileRunAttentionCountProvider('host').overrideWith((ref) async => 2),
    mobileQuestionUnreadCountProvider('host').overrideWith((ref) async => 1),
    mobileAutomationAttentionCountProvider('host')
        .overrideWith((ref) async => 0),
    if (runs != null)
      mobileRunsClientProvider('host').overrideWith((ref) async => runs),
    if (inbox != null)
      mobileInboxClientProvider('host').overrideWith((ref) async => inbox),
  ],
  child: MaterialApp(home: HostDashboardScreen(host: _host)),
);

Future<void> _scrollToActivity(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const ValueKey<String>('activity-row-automations')),
    200,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one Activity card lists Runs, Questions and Automations', (
    tester,
  ) async {
    await tester.pumpWidget(
      _dashboard(supportsInbox: true, supportsRuns: true),
    );
    await _scrollToActivity(tester);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.byTooltip('Open Runs'), findsOneWidget);
    expect(find.byTooltip('Open Questions'), findsOneWidget);
    expect(find.byTooltip('Open Automations'), findsOneWidget);
    expect(find.text('2 Need Attention'), findsOneWidget);
    expect(find.text('1 New Reply'), findsOneWidget);
    expect(find.byTooltip('Open Inbox'), findsNothing);
  });

  testWidgets('an older host shows only the parts it supports', (tester) async {
    await tester.pumpWidget(
      _dashboard(supportsInbox: false, supportsRuns: false),
    );
    await _scrollToActivity(tester);
    expect(find.byTooltip('Open Automations'), findsOneWidget);
    expect(find.byTooltip('Open Runs'), findsNothing);
    expect(find.byTooltip('Open Questions'), findsNothing);
  });

  testWidgets('each row opens Activity at its part', (tester) async {
    final runs = FakeRunsClient();
    addTearDown(runs.dispose);
    await tester.pumpWidget(
      _dashboard(supportsInbox: true, supportsRuns: true, runs: runs),
    );
    await _scrollToActivity(tester);
    await tester.tap(find.byTooltip('Open Runs'));
    await tester.pumpAndSettle();
    final screen = tester.widget<ActivityScreen>(find.byType(ActivityScreen));
    expect(screen.initialSection, ActivitySection.runs);
    expect(find.text('Fix flaky login test'), findsOneWidget);
  });

  testWidgets('Questions has no Agent Conversations and never asks for them', (
    tester,
  ) async {
    final inbox = FakeInboxClient();
    addTearDown(inbox.dispose);
    await tester.pumpWidget(
      _dashboard(supportsInbox: true, supportsRuns: false, inbox: inbox),
    );
    await _scrollToActivity(tester);
    await tester.tap(find.byTooltip('Open Questions'));
    await tester.pumpAndSettle();
    expect(find.text('Which tests cover login?'), findsOneWidget);
    expect(find.text('Agent Conversations'), findsNothing);
    expect(
      inbox.calls.where((call) => call.type.startsWith('inbox.conversation')),
      isEmpty,
    );
  });
}
