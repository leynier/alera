import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
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

  testWidgets('an interrupted agent adds the Interrupted badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _rowApp(<AgentPresenceSummary>[_presence('done', interrupted: true)]),
    );

    final badge = tester.widget<AleraBadge>(find.byKey(badgeKey));
    expect(badge.label, 'Interrupted');
    expect(badge.tone, AleraBadgeTone.error);
  });

  testWidgets('working and idle rows show no badge', (tester) async {
    await tester.pumpWidget(
      _rowApp(<AgentPresenceSummary>[_presence('working')]),
    );
    expect(find.byKey(badgeKey), findsNothing);

    await tester.pumpWidget(_rowApp(const <AgentPresenceSummary>[]));
    expect(find.byKey(badgeKey), findsNothing);
  });

  testWidgets(
    'a working secondary agent hides Done and keeps the green check',
    (tester) async {
      await tester.pumpWidget(
        _rowApp(<AgentPresenceSummary>[
          _presence('done'),
          _presence('working', tabId: 'tab-2', sessionId: 'session-2'),
        ]),
      );

      expect(find.byKey(badgeKey), findsNothing);
      _expectLeadingIcon(tester, AleraIcons.success, AleraTokens.success);
    },
  );

  testWidgets('a blocked secondary agent badges the row over a done primary', (
    tester,
  ) async {
    await tester.pumpWidget(
      _rowApp(<AgentPresenceSummary>[
        _presence('done'),
        _presence('blocked', tabId: 'tab-2', sessionId: 'session-2'),
      ]),
    );

    expect(tester.widget<AleraBadge>(find.byKey(badgeKey)).label, 'Blocked');
    _expectLeadingIcon(tester, AleraIcons.success, AleraTokens.success);
  });

  testWidgets('a blocked primary agent keeps its red glyph', (tester) async {
    await tester.pumpWidget(
      _rowApp(<AgentPresenceSummary>[_presence('blocked')]),
    );

    expect(tester.widget<AleraBadge>(find.byKey(badgeKey)).label, 'Blocked');
    _expectLeadingIcon(tester, AleraIcons.notifications, AleraTokens.error);
  });

  testWidgets('the badge shows without a primary agent', (tester) async {
    await tester.pumpWidget(
      _rowApp(<AgentPresenceSummary>[
        _presence('waiting', tabId: 'tab-2', sessionId: 'session-2'),
        _presence('done', tabId: 'tab-3', sessionId: 'session-3'),
      ]),
    );

    expect(
      tester.widget<AleraBadge>(find.byKey(badgeKey)).label,
      'Needs Input',
    );
    expect(find.bySemanticsLabel(RegExp('Terminal open')), findsOneWidget);
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

  testWidgets('the badge keeps the row height and is spoken', (tester) async {
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
    // The badge can come from a secondary agent, so it speaks for itself.
    expect(find.bySemanticsLabel(RegExp('Needs Input')), findsOneWidget);
    semantics.dispose();
  });
}

void _expectLeadingIcon(WidgetTester tester, IconData icon, Color color) {
  final glyph = tester.widget<Icon>(
    find.descendant(
      of: find.byKey(const Key('workspace-status-glyph')),
      matching: find.byType(Icon),
    ),
  );
  expect(glyph.icon, icon);
  expect(glyph.color, color);
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
