import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_run_groups.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _t0 = .utc(2026, 7, 4);

WorkspaceAgentRun _run(String id, AgentStatusState state, {bool? interrupted}) {
  final tab = WorkspaceTabRecord(
    id: id,
    workspaceId: 'w-1',
    kind: .terminal,
    title: id,
    createdAt: _t0,
    updatedAt: _t0,
  );
  return WorkspaceAgentRun(
    tab: tab,
    status: AgentStatusEntry(
      terminalSessionId: tab.terminalSessionId,
      workspaceId: tab.workspaceId,
      tabId: tab.id,
      agentType: .claude,
      state: state,
      prompt: 'Prompt',
      updatedAt: _t0,
      stateStartedAt: _t0,
      interrupted: interrupted,
    ),
  );
}

void main() {
  test('groups runs by state in display order', () {
    final groups = groupWorkspaceAgentRuns(<WorkspaceAgentRun>[
      _run('t-1', .done),
      _run('t-2', .working),
      _run('t-3', .waiting),
      _run('t-4', .working),
    ]);

    expect(groups.map((g) => g.kind), <WorkspaceAgentGroupKind>[
      WorkspaceAgentGroupKind.waiting,
      WorkspaceAgentGroupKind.working,
      WorkspaceAgentGroupKind.done,
    ]);
    expect(
      groups
          .firstWhere((g) => g.kind == WorkspaceAgentGroupKind.working)
          .runs
          .length,
      2,
    );
  });

  test('interruption overrides the reported state', () {
    final groups = groupWorkspaceAgentRuns(<WorkspaceAgentRun>[
      _run('t-1', .done, interrupted: true),
    ]);

    expect(groups.single.kind, WorkspaceAgentGroupKind.interrupted);
  });

  test('an empty run list produces no groups', () {
    expect(groupWorkspaceAgentRuns(const <WorkspaceAgentRun>[]), isEmpty);
  });
}
