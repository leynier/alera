import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/presentation/agent_identity_icon.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_run_groups.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/presentation/widgets/workspace_agent_compact_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('keeps each agent icon in place when the runs reorder', (
    tester,
  ) async {
    final cursor = _run(.cursor, tabId: 'tab-cursor');
    final claude = _run(.claude, tabId: 'tab-claude');

    await _pumpSummary(tester, <WorkspaceAgentRun>[claude, cursor]);
    final initial = _iconAgentTypes(tester);

    // Runs are ordered by recency, so any hook event from either agent flips
    // the list. The icons must not follow it.
    await _pumpSummary(tester, <WorkspaceAgentRun>[cursor, claude]);

    expect(initial, <AgentType>[AgentType.claude, AgentType.cursor]);
    expect(_iconAgentTypes(tester), initial);
  });

  testWidgets('shows one icon per agent type in the group', (tester) async {
    await _pumpSummary(tester, <WorkspaceAgentRun>[
      _run(.cursor, tabId: 'tab-1'),
      _run(.cursor, tabId: 'tab-2'),
      _run(.claude, tabId: 'tab-3'),
    ]);

    expect(_iconAgentTypes(tester), <AgentType>[
      AgentType.claude,
      AgentType.cursor,
    ]);
  });
}

Future<void> _pumpSummary(
  WidgetTester tester,
  List<WorkspaceAgentRun> runs,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WorkspaceAgentCompactSummary(
          groups: groupWorkspaceAgentRuns(runs),
          expanded: false,
          onToggle: () {},
        ),
      ),
    ),
  );
  await tester.pump();
}

List<AgentType> _iconAgentTypes(WidgetTester tester) {
  return tester
      .widgetList<AgentIdentityIcon>(find.byType(AgentIdentityIcon))
      .map((icon) => icon.agentType)
      .toList();
}

WorkspaceAgentRun _run(AgentType agentType, {required String tabId}) {
  final now = DateTime.utc(2026, 5, 26, 12);
  return WorkspaceAgentRun(
    tab: WorkspaceTabRecord(
      id: tabId,
      workspaceId: 'workspace-1',
      title: 'Terminal',
      createdAt: now,
      updatedAt: now,
    ),
    status: AgentStatusEntry(
      terminalSessionId: 'session-$tabId',
      workspaceId: 'workspace-1',
      tabId: tabId,
      agentType: agentType,
      state: .working,
      prompt: 'Run tests',
      updatedAt: now,
      stateStartedAt: now,
    ),
  );
}
