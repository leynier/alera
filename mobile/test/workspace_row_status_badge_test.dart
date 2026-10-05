import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_workspace_rows.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_listing_tree.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_row_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const badgeKey = Key('workspace-status-badge');

  for (final (state, label, tone) in <(String, String, AleraBadgeTone)>[
    ('waiting', 'Needs Input', AleraBadgeTone.attention),
    ('blocked', 'Blocked', AleraBadgeTone.error),
    ('done', 'Done', AleraBadgeTone.success),
  ]) {
    testWidgets('a $state agent adds the $label badge', (tester) async {
      await tester.pumpWidget(
        _rowApp(<AgentPresenceSummary>[_presence(state)]),
      );

      final badge = tester.widget<AleraBadge>(find.byKey(badgeKey));
      expect(badge.label, label);
      expect(badge.tone, tone);
    });
  }

  testWidgets('working, interrupted, and idle rows show no badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _rowApp(<AgentPresenceSummary>[_presence('working')]),
    );
    expect(find.byKey(badgeKey), findsNothing);

    await tester.pumpWidget(
      _rowApp(<AgentPresenceSummary>[_presence('waiting', interrupted: true)]),
    );
    expect(find.byKey(badgeKey), findsNothing);

    await tester.pumpWidget(_rowApp(const <AgentPresenceSummary>[]));
    expect(find.byKey(badgeKey), findsNothing);
  });

  testWidgets('the most urgent agent picks the badge', (tester) async {
    await tester.pumpWidget(
      _rowApp(<AgentPresenceSummary>[
        _presence('done'),
        _presence('blocked', tabId: 'tab-2', sessionId: 'session-2'),
      ]),
    );

    expect(tester.widget<AleraBadge>(find.byKey(badgeKey)).label, 'Blocked');
  });

  testWidgets('the badge keeps the row height and speaks once', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_rowApp(const <AgentPresenceSummary>[]));
    final idleHeight = tester
        .getSize(find.byType(MobileWorkspaceListRow))
        .height;

    await tester.pumpWidget(
      _rowApp(<AgentPresenceSummary>[_presence('waiting')]),
    );
    expect(
      tester.getSize(find.byType(MobileWorkspaceListRow)).height,
      idleHeight,
    );
    // The row's tap target merges its children, so match within its label.
    expect(
      find.bySemanticsLabel(RegExp('Agent waiting for input')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(RegExp('Needs Input')), findsNothing);
    semantics.dispose();
  });
}

Widget _rowApp(List<AgentPresenceSummary> agentPresence) {
  return MaterialApp(
    theme: buildAleraMobileDarkTheme(),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: MobileWorkspaceListRow(
          row: const MobileWorkspaceEntryRow(
            entry: WorkspaceTreeEntry(
              workspace: WorkspaceSummary(
                id: 'workspace-1',
                projectId: 'project-1',
                name: 'Workspace',
                path: '/repo',
              ),
              depth: 0,
              visibleChildCount: 0,
              childrenCollapsed: false,
            ),
          ),
          onTap: () {},
          onLongPress: () {},
          onMore: () {},
          onToggleChildren: () {},
          terminalTabCount: 1,
          agentsExpanded: false,
          onToggleAgents: () {},
          onAgentTap: (_) {},
          onCloseAgent: (_) {},
          agentPresence: agentPresence,
          // Keeps the single agent on the row instead of the nested tray, so
          // the height comparison isolates the badge.
          mainTabIds: const <String>{'tab-1'},
        ),
      ),
    ),
  );
}

AgentPresenceSummary _presence(
  String state, {
  bool? interrupted,
  String tabId = 'tab-1',
  String sessionId = 'session-1',
}) {
  return AgentPresenceSummary(
    terminalSessionId: sessionId,
    workspaceId: 'workspace-1',
    tabId: tabId,
    agentType: 'codex',
    state: state,
    interrupted: interrupted,
  );
}
