import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('workspace agent status projection', () {
    test('prioritizes attention states over working and done', () {
      final doneTab = _tab('tab-done');
      final workingTab = _tab('tab-working');
      final waitingTab = _tab('tab-waiting');
      final blockedTab = _tab('tab-blocked');

      final status = aggregateWorkspaceAgentStatus(
        tabs: <WorkspaceTabRecord>[doneTab, workingTab, waitingTab, blockedTab],
        agentStatuses: <String, AgentStatusEntry>{
          doneTab.terminalSessionId: _entry(doneTab, AgentStatusState.done),
          workingTab.terminalSessionId: _entry(
            workingTab,
            AgentStatusState.working,
          ),
          waitingTab.terminalSessionId: _entry(
            waitingTab,
            AgentStatusState.waiting,
          ),
          blockedTab.terminalSessionId: _entry(
            blockedTab,
            AgentStatusState.blocked,
          ),
        },
      );

      expect(status?.tabId, blockedTab.id);
    });

    test('uses most recent update when priorities match', () {
      final firstTab = _tab('tab-1');
      final secondTab = _tab('tab-2');

      final status = aggregateWorkspaceAgentStatus(
        tabs: <WorkspaceTabRecord>[firstTab, secondTab],
        agentStatuses: <String, AgentStatusEntry>{
          firstTab.terminalSessionId: _entry(
            firstTab,
            AgentStatusState.waiting,
            updatedAt: DateTime.utc(2026, 5, 26, 12),
          ),
          secondTab.terminalSessionId: _entry(
            secondTab,
            AgentStatusState.waiting,
            updatedAt: DateTime.utc(2026, 5, 26, 12, 1),
          ),
        },
      );

      expect(status?.tabId, secondTab.id);
    });

    test('ignores non-terminal tabs and stale tab ids', () {
      final browserTab = _tab('browser', kind: WorkspaceTabKind.browser);
      final terminalTab = _tab('terminal');

      final status = aggregateWorkspaceAgentStatus(
        tabs: <WorkspaceTabRecord>[browserTab, terminalTab],
        agentStatuses: <String, AgentStatusEntry>{
          browserTab.terminalSessionId: _entry(
            browserTab,
            AgentStatusState.blocked,
          ),
          terminalTab.terminalSessionId: _entry(
            terminalTab,
            AgentStatusState.working,
            tabId: 'old-tab',
          ),
        },
      );

      expect(status, isNull);
    });
  });
}

WorkspaceTabRecord _tab(
  String id, {
  WorkspaceTabKind kind = WorkspaceTabKind.terminal,
}) {
  return WorkspaceTabRecord(
    id: id,
    workspaceId: 'workspace-1',
    title: id,
    kind: kind,
    createdAt: DateTime.utc(2026, 5, 26),
    updatedAt: DateTime.utc(2026, 5, 26),
  );
}

AgentStatusEntry _entry(
  WorkspaceTabRecord tab,
  AgentStatusState state, {
  DateTime? updatedAt,
  String? tabId,
}) {
  final timestamp = updatedAt ?? DateTime.utc(2026, 5, 26);
  return AgentStatusEntry(
    terminalSessionId: tab.terminalSessionId,
    workspaceId: tab.workspaceId,
    tabId: tabId ?? tab.id,
    agentType: AgentType.codex,
    state: state,
    prompt: '',
    updatedAt: timestamp,
    stateStartedAt: timestamp,
  );
}
