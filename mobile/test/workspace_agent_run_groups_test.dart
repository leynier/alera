import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_agent_run_groups.dart';
import 'package:flutter_test/flutter_test.dart';

AgentPresenceSummary _presence({
  required String state,
  String agentType = 'codex',
  bool? interrupted,
  String handle = 't1',
}) {
  return AgentPresenceSummary(
    terminalSessionId: handle,
    workspaceId: 'ws',
    tabId: 'tab-$handle',
    agentType: agentType,
    state: state,
    interrupted: interrupted,
  );
}

void main() {
  test('groups by state in attention-first order', () {
    final groups = groupWorkspaceAgentRuns(<AgentPresenceSummary>[
      _presence(state: 'done', agentType: 'codex', handle: '1'),
      _presence(state: 'working', agentType: 'opencode', handle: '2'),
      _presence(state: 'waiting', agentType: 'claude', handle: '3'),
      _presence(state: 'blocked', agentType: 'cursor', handle: '4'),
    ]);

    expect(
      groups.map((group) => group.kind).toList(),
      <WorkspaceAgentGroupKind>[
        WorkspaceAgentGroupKind.waiting,
        WorkspaceAgentGroupKind.blocked,
        WorkspaceAgentGroupKind.working,
        WorkspaceAgentGroupKind.done,
      ],
    );
  });

  test('interrupted wins over reported state', () {
    final groups = groupWorkspaceAgentRuns(<AgentPresenceSummary>[
      _presence(state: 'working', interrupted: true, handle: '1'),
      _presence(state: 'done', handle: '2'),
    ]);

    expect(groups.first.kind, WorkspaceAgentGroupKind.interrupted);
    expect(groups.first.runs, hasLength(1));
    expect(groups.last.kind, WorkspaceAgentGroupKind.done);
  });

  test('empty presence yields no groups', () {
    expect(groupWorkspaceAgentRuns(const <AgentPresenceSummary>[]), isEmpty);
  });
}
