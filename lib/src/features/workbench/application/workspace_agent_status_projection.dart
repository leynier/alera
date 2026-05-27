import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';

AgentStatusEntry? aggregateWorkspaceAgentStatus({
  required Iterable<WorkspaceTabRecord> tabs,
  required Map<String, AgentStatusEntry> agentStatuses,
}) {
  AgentStatusEntry? selected;
  for (final tab in tabs) {
    if (tab.kind != WorkspaceTabKind.terminal) {
      continue;
    }
    final entry = agentStatuses[tab.terminalSessionId];
    if (entry == null ||
        entry.workspaceId != tab.workspaceId ||
        entry.tabId != tab.id) {
      continue;
    }
    if (selected == null || _compareWorkspaceStatus(entry, selected) > 0) {
      selected = entry;
    }
  }
  return selected;
}

int _compareWorkspaceStatus(AgentStatusEntry next, AgentStatusEntry current) {
  final nextPriority = _workspaceStatusPriority(next.state);
  final currentPriority = _workspaceStatusPriority(current.state);
  if (nextPriority != currentPriority) {
    return nextPriority - currentPriority;
  }
  return next.updatedAt.compareTo(current.updatedAt);
}

int _workspaceStatusPriority(AgentStatusState state) {
  return switch (state) {
    AgentStatusState.blocked => 4,
    AgentStatusState.waiting => 3,
    AgentStatusState.working => 2,
    AgentStatusState.done => 1,
  };
}
