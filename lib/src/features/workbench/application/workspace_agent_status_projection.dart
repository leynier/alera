import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera/src/features/workbench/application/workspace_chat_agent_runs.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';

/// An agent in one of the workspace's tabs: a terminal agent reported by its
/// hooks, or an agent chat when [chat] is set.
class const WorkspaceAgentRun({
  required final WorkspaceTabRecord tab,
  required final AgentStatusEntry status,
  final WorkspaceChatRun? chat,
}) {
  /// The agent mark to draw; `null` means the generic agent icon.
  AgentType? get agentType => chat == null ? status.agentType : chat!.agentType;

  /// Groups runs that share a mark, telling unmarked chat providers apart.
  String get identityKey => chat == null
      ? status.agentType.key
      : chat!.agentType?.key ?? 'chat:${chat!.provider}';
}

/// Runs keep the incoming tab order (creation order): sorting by status or
/// recency would reshuffle sidebar rows on every agent hook event. With
/// [chats] (`agentChat.list` entries by chat id), agent chat tabs become runs
/// too, each delegated child chat placed right after its parent chat when
/// both live in this workspace, so every chat keeps its own tree.
List<WorkspaceAgentRun> visibleWorkspaceAgentRuns({
  required Iterable<WorkspaceTabRecord> tabs,
  required Map<String, AgentStatusEntry> agentStatuses,
  Map<String, ChatAttentionEntry> chats = const <String, ChatAttentionEntry>{},
}) {
  final runs = <WorkspaceAgentRun>[];
  final listed = [for (final tab in tabs) ?chatEntryForTab(tab, chats)];
  final covered = chatParentsWithListedChildInput(listed);
  for (final tab in tabs) {
    if (chatEntryForTab(tab, chats) case final chat?) {
      final level = chat.levelAmong(covered);
      runs.add(
        WorkspaceAgentRun(
          tab: tab,
          status: chatAgentStatus(tab, chat, level),
          chat: workspaceChatRun(chat, level),
        ),
      );
      continue;
    }
    final entry = matchingAgentStatusForTab(
      tab: tab,
      agentStatuses: agentStatuses,
    );
    if (entry == null) {
      continue;
    }
    runs.add(WorkspaceAgentRun(tab: tab, status: entry));
  }
  return _nestChildChats(runs);
}

/// Moves each chat whose parent chat is also listed directly below that
/// parent (after the parent's earlier children), recording its depth. A
/// cycle or a missing parent leaves the chat where it was.
List<WorkspaceAgentRun> _nestChildChats(List<WorkspaceAgentRun> runs) {
  final byChat = <String, WorkspaceAgentRun>{
    for (final run in runs)
      if (run.chat case final chat?) chat.chatId: run,
  };
  final children = <String, List<WorkspaceAgentRun>>{};
  bool nested(WorkspaceAgentRun run) {
    final parent = run.chat?.parentChatId;
    return parent != null &&
        parent != run.chat!.chatId &&
        byChat.containsKey(parent);
  }

  for (final run in runs) {
    if (nested(run)) {
      children.putIfAbsent(run.chat!.parentChatId!, () => []).add(run);
    }
  }
  if (children.isEmpty) return runs;
  final ordered = <WorkspaceAgentRun>[];
  final placed = <String>{};
  void place(WorkspaceAgentRun run, int depth) {
    final chat = run.chat;
    if (chat != null && !placed.add(chat.chatId)) return;
    ordered.add(
      chat == null || chat.depth == depth
          ? run
          : WorkspaceAgentRun(
              tab: run.tab,
              status: run.status,
              chat: chat.atDepth(depth),
            ),
    );
    if (chat == null) return;
    for (final child in children[chat.chatId] ?? const <WorkspaceAgentRun>[]) {
      place(child, depth + 1);
    }
  }

  for (final run in runs) {
    if (!nested(run)) place(run, 0);
  }
  // Chats only reachable through a cycle have no root above them.
  for (final run in runs) {
    if (run.chat case final chat? when !placed.contains(chat.chatId)) {
      place(run, 0);
    }
  }
  return ordered;
}

AgentStatusEntry? aggregateWorkspaceAgentStatus({
  required Iterable<WorkspaceTabRecord> tabs,
  required Map<String, AgentStatusEntry> agentStatuses,
}) {
  return mostUrgentWorkspaceAgentRun(
    visibleWorkspaceAgentRuns(tabs: tabs, agentStatuses: agentStatuses),
  )?.status;
}

/// Picks the run that should drive the workspace glyph.
///
/// Visible runs stay in creation order so expanded sidebar rows do not
/// reshuffle; this ranking is only for the single status shown beside the
/// workspace name.
WorkspaceAgentRun? mostUrgentWorkspaceAgentRun(
  Iterable<WorkspaceAgentRun> runs,
) {
  final iterator = runs.iterator;
  if (!iterator.moveNext()) {
    return null;
  }
  var mostUrgent = iterator.current;
  while (iterator.moveNext()) {
    final run = iterator.current;
    if (_compareAgentRuns(run, mostUrgent) < 0) {
      mostUrgent = run;
    }
  }
  return mostUrgent;
}

AgentStatusEntry? matchingAgentStatusForTab({
  required WorkspaceTabRecord tab,
  required Map<String, AgentStatusEntry> agentStatuses,
}) {
  if (tab.kind != WorkspaceTabKind.terminal) {
    return null;
  }
  final entry = agentStatuses[tab.terminalSessionId];
  if (entry == null ||
      entry.workspaceId != tab.workspaceId ||
      entry.tabId != tab.id ||
      entry.terminalSessionId != tab.terminalSessionId) {
    return null;
  }
  return entry;
}

// Urgency ranking for the aggregate workspace status only; row order stays
// in creation order.
int _compareAgentRuns(WorkspaceAgentRun a, WorkspaceAgentRun b) {
  final aPriority = _workspaceStatusPriority(a.status);
  final bPriority = _workspaceStatusPriority(b.status);
  if (aPriority != bPriority) {
    return bPriority.compareTo(aPriority);
  }
  final recency = b.status.updatedAt.compareTo(a.status.updatedAt);
  if (recency != 0) {
    return recency;
  }
  return a.tab.createdAt.compareTo(b.tab.createdAt);
}

/// Agents that currently need the user: waiting, blocked, or interrupted.
int pendingReviewAgentCount(Iterable<WorkspaceAgentRun> runs) {
  var count = 0;
  for (final run in runs) {
    if (agentStatusNeedsYou(run.status)) {
      count += 1;
    }
  }
  return count;
}

/// Shared with Agent Activity: interruption and waiting/blocked need the user.
bool agentStatusNeedsYou(AgentStatusEntry status) {
  if (status.interrupted ?? false) {
    return true;
  }
  return switch (status.state) {
    AgentStatusState.waiting || AgentStatusState.blocked => true,
    AgentStatusState.working || AgentStatusState.done => false,
  };
}

// Compact tray and Agent Activity treat interruption as attention, not as
// a finished run. Ranking it above working/done keeps the glyph from
// turning green (or spinning) over a leftover interrupted tab.
int _workspaceStatusPriority(AgentStatusEntry status) {
  if (status.interrupted ?? false) {
    return 3;
  }
  return switch (status.state) {
    AgentStatusState.blocked => 5,
    AgentStatusState.waiting => 4,
    AgentStatusState.working => 2,
    AgentStatusState.done => 1,
  };
}
