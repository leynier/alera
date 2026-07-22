import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_agent_run_groups.dart';
import 'package:alera_mobile/src/features/workbench/presentation/mobile_workspace_agent_compact_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AgentPresenceSummary _presence({
  required String state,
  required String agentType,
  required String handle,
}) {
  return AgentPresenceSummary(
    terminalSessionId: handle,
    workspaceId: 'ws',
    tabId: 'tab-$handle',
    agentType: agentType,
    state: state,
  );
}

void main() {
  testWidgets('compact summary shows clusters and toggles on tap', (
    tester,
  ) async {
    var expanded = false;
    final groups = groupWorkspaceAgentRuns(<AgentPresenceSummary>[
      _presence(state: 'working', agentType: 'opencode', handle: '1'),
      _presence(state: 'done', agentType: 'codex', handle: '2'),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAleraMobileDarkTheme(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => MobileWorkspaceAgentCompactSummary(
              groups: groups,
              expanded: expanded,
              onToggle: () => setState(() => expanded = !expanded),
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(AleraIcons.chevronDown), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(AleraIcons.success), findsOneWidget);

    await tester.tap(find.byType(MobileWorkspaceAgentCompactSummary));
    await tester.pump();

    expect(find.byIcon(AleraIcons.chevronUp), findsOneWidget);
  });
}
