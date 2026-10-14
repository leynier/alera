import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';

/// The agent chat behind a workspace agent row. Terminal rows have none.
class const WorkspaceChatRun({
  required final String chatId,
  required final String provider,
  required final String title,
  required final ChatAttentionLevel level,
  final String? parentChatId,
  final int openChildTaskCount = 0,
  final int depth = 0,
}) {
  /// The agent mark for the provider; `null` falls back to the generic
  /// agent icon (Muse, ACP agents).
  AgentType? get agentType => agentChatAgentType(provider);

  WorkspaceChatRun atDepth(int depth) => depth == this.depth
      ? this
      : WorkspaceChatRun(
          chatId: chatId,
          provider: provider,
          title: title,
          level: level,
          parentChatId: parentChatId,
          openChildTaskCount: openChildTaskCount,
          depth: depth,
        );

  @override
  bool operator ==(Object other) =>
      other is WorkspaceChatRun &&
      other.chatId == chatId &&
      other.provider == provider &&
      other.title == title &&
      other.level == level &&
      other.parentChatId == parentChatId &&
      other.openChildTaskCount == openChildTaskCount &&
      other.depth == depth;

  @override
  int get hashCode => Object.hash(
    chatId,
    provider,
    title,
    level,
    parentChatId,
    openChildTaskCount,
    depth,
  );
}

/// The chat entry bound to an `agentChat` [tab], if the runtime lists it in
/// the tab's workspace.
ChatAttentionEntry? chatEntryForTab(
  WorkspaceTabRecord tab,
  Map<String, ChatAttentionEntry> chats,
) {
  if (tab.kind != WorkspaceTabKind.agentChat) return null;
  final chatId = tab.agentChatId;
  if (chatId == null) return null;
  final entry = chats[chatId];
  if (entry == null || entry.workspaceId != tab.workspaceId) return null;
  return entry;
}

/// A chat expressed in the terminal agent vocabulary, so the sidebar, the
/// Workspace Details card and the tray badge rank and count it with the same
/// rules. A failed chat reads as interrupted, which needs the person; an
/// idle or unread chat reads as done. [level] comes from
/// [ChatAttentionEntry.levelAmong], so a listed child that needs input is
/// counted once, on itself.
AgentStatusEntry chatAgentStatus(
  WorkspaceTabRecord tab,
  ChatAttentionEntry entry,
  ChatAttentionLevel level,
) {
  // An idle chat with nothing unread is not a finished run waiting for
  // review; dating it to the epoch makes Agent Activity read it as stale.
  final at = level == ChatAttentionLevel.idle
      ? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
      : entry.updatedAt;
  return AgentStatusEntry(
    terminalSessionId: '',
    workspaceId: tab.workspaceId,
    tabId: tab.id,
    // Only a fallback for code that reads the type off the status: chat
    // rows draw their mark from [WorkspaceChatRun.agentType].
    agentType: agentChatAgentType(entry.provider) ?? AgentType.codex,
    state: switch (level) {
      ChatAttentionLevel.needsInput => AgentStatusState.waiting,
      ChatAttentionLevel.working ||
      ChatAttentionLevel.waitingOnTasks => AgentStatusState.working,
      ChatAttentionLevel.failed ||
      ChatAttentionLevel.unread ||
      ChatAttentionLevel.idle => AgentStatusState.done,
    },
    prompt: '',
    updatedAt: at,
    stateStartedAt: at,
    interrupted: level == ChatAttentionLevel.failed ? true : null,
  );
}

WorkspaceChatRun workspaceChatRun(
  ChatAttentionEntry entry,
  ChatAttentionLevel level,
) => WorkspaceChatRun(
  chatId: entry.chatId,
  provider: entry.provider,
  title: entry.title,
  level: level,
  parentChatId: entry.parentChatId,
  openChildTaskCount: entry.openChildTaskCount,
);

/// What a chat row says about its state, beside the shared state glyph.
String workspaceChatRunStateLabel(WorkspaceChatRun chat) =>
    switch (chat.level) {
      ChatAttentionLevel.needsInput => 'Needs input',
      ChatAttentionLevel.failed => 'Stopped',
      ChatAttentionLevel.unread => 'Unread result',
      ChatAttentionLevel.working => 'Working',
      ChatAttentionLevel.waitingOnTasks => 'Waiting on delegated tasks',
      ChatAttentionLevel.idle => 'Idle',
    };
