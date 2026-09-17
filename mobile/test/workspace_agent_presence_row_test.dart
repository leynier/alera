import 'package:alera_mobile/src/app/theme/alera_theme.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_workspace_rows.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_listing_tree.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';
import 'package:alera_mobile/src/features/workbench/presentation/mobile_workspace_agent_compact_summary.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_row_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('expanded agent rows show title with activity as subtitle', (
    tester,
  ) async {
    await tester.pumpWidget(
      _rowApp(<AgentPresenceSummary>[
        _presence(
          title: 'Map Monetization',
          state: 'waiting',
          lastAssistantMessage: '**paymentBroker**',
        ),
        _presence(
          title: 'Other Agent',
          state: 'done',
          tabId: 'tab-2',
          sessionId: 'session-2',
        ),
      ]),
    );

    final title = tester.widget<Text>(find.text('Map Monetization'));
    final activity = tester.widget<Text>(find.text('**paymentBroker**'));
    expect(title.style?.color, AleraTokens.foreground);
    expect(title.style?.fontWeight, FontWeight.w600);
    expect(activity.style?.color, AleraTokens.foregroundMuted);
    expect(find.text('Codex · Waiting for input'), findsNothing);
  });

  testWidgets('working tool activity does not replace the title', (
    tester,
  ) async {
    await tester.pumpWidget(
      _rowApp(<AgentPresenceSummary>[
        _presence(
          title: 'Map Monetization',
          state: 'working',
          toolName: 'Read',
          toolInput: 'lib/foo.dart',
        ),
        _presence(
          title: 'Other Agent',
          state: 'done',
          tabId: 'tab-2',
          sessionId: 'session-2',
        ),
      ]),
    );

    expect(find.text('Map Monetization'), findsOneWidget);
    expect(find.text('Read: lib/foo.dart'), findsOneWidget);
  });

  testWidgets('missing title uses the agent name instead of activity', (
    tester,
  ) async {
    await tester.pumpWidget(
      _rowApp(<AgentPresenceSummary>[
        _presence(
          state: 'waiting',
          lastAssistantMessage: 'Waiting for approval',
        ),
        _presence(
          title: 'Other Agent',
          state: 'done',
          tabId: 'tab-2',
          sessionId: 'session-2',
        ),
      ]),
    );

    final title = tester.widget<Text>(find.text('Codex'));
    expect(title.style?.color, AleraTokens.foreground);
    expect(find.text('Waiting for approval'), findsOneWidget);
    expect(find.text('Codex · Waiting for input'), findsNothing);
  });

  testWidgets(
    'a single agent shows its identity on the workspace without nested rows',
    (tester) async {
      await tester.pumpWidget(
        _rowApp(<AgentPresenceSummary>[
          _presence(
            title: 'Map Monetization',
            state: 'working',
            toolName: 'Read',
            toolInput: 'lib/foo.dart',
          ),
        ]),
      );

      expect(find.byKey(const Key('workspace-primary-agent')), findsOneWidget);
      expect(
        tester
            .widget<AgentIdentityIcon>(
              find.byKey(const Key('workspace-primary-agent')),
            )
            .agentType,
        'codex',
      );
      expect(find.byType(MobileWorkspaceAgentCompactSummary), findsNothing);
      expect(find.text('Map Monetization'), findsNothing);
      expect(find.text('Read: lib/foo.dart'), findsNothing);
    },
  );

  testWidgets(
    'two agents keep nested rows and omit the workspace primary icon',
    (tester) async {
      await tester.pumpWidget(
        _rowApp(<AgentPresenceSummary>[
          _presence(title: 'Map Monetization', state: 'working'),
          _presence(
            title: 'Other Agent',
            state: 'done',
            tabId: 'tab-2',
            sessionId: 'session-2',
          ),
        ]),
      );

      expect(find.byKey(const Key('workspace-primary-agent')), findsNothing);
      expect(find.byType(MobileWorkspaceAgentCompactSummary), findsOneWidget);
      expect(find.text('Map Monetization'), findsOneWidget);
      expect(find.text('Other Agent'), findsOneWidget);
    },
  );
}

Widget _rowApp(List<AgentPresenceSummary> agentPresence) {
  return MaterialApp(
    theme: buildAleraMobileDarkTheme(),
    home: Scaffold(
      body: MobileWorkspaceListRow(
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
        agentsExpanded: true,
        onToggleAgents: () {},
        onAgentTap: (_) {},
        onCloseAgent: (_) {},
        agentPresence: agentPresence,
      ),
    ),
  );
}

AgentPresenceSummary _presence({
  String title = '',
  required String state,
  String? toolName,
  String? toolInput,
  String? lastAssistantMessage,
  String tabId = 'tab-1',
  String sessionId = 'session-1',
}) {
  return AgentPresenceSummary(
    terminalSessionId: sessionId,
    workspaceId: 'workspace-1',
    tabId: tabId,
    agentType: 'codex',
    state: state,
    title: title,
    toolName: toolName,
    toolInput: toolInput,
    lastAssistantMessage: lastAssistantMessage,
  );
}
