import 'package:alera_agent_chat/src/agent_chat_change.dart';
import 'package:alera_agent_chat/src/agent_chat_modes.dart';
import 'package:alera_agent_chat/src/agent_chat_summary.dart';

/// Live child task counts of a parent chat.
typedef ChatTaskChildren = ({int open, bool needsInput});

/// How much a chat needs someone, most urgent first. The order is the tab
/// dot and sidebar order: needs input, failed, unread result, working,
/// waiting on tasks, idle.
enum ChatAttentionLevel {
  needsInput,
  failed,
  unread,
  working,
  waitingOnTasks,
  idle,
}

/// What the sidebar and notices know about one chat without opening it.
/// Seeded from `agentChat.list` and kept current from its changes.
class const ChatAttentionEntry({
  required final String chatId,
  required final String workspaceId,
  required final String title,
  required final DateTime updatedAt,
  final String? tabId,
  final String provider = '',
  final AgentChatSessionStatus status = AgentChatSessionStatus.ready,
  final bool hasPendingRequests = false,
  final int openChildTaskCount = 0,
  final bool childNeedsInput = false,
  final bool unread = false,
  final String? parentChatId,
}) {
  factory fromSummary(AgentChatSummary summary) => ChatAttentionEntry(
    chatId: summary.chatId,
    workspaceId: summary.workspaceId,
    title: summary.title,
    updatedAt: summary.updatedAt,
    tabId: summary.tabId,
    provider: summary.provider,
    status: summary.status,
    hasPendingRequests: summary.pendingRequestCount > 0,
    openChildTaskCount: summary.openChildTaskCount,
    childNeedsInput: summary.childNeedsInput,
    unread: summary.unread,
    parentChatId: summary.parentChatId,
  );

  ChatAttentionLevel get level =>
      childNeedsInput ? ChatAttentionLevel.needsInput : ownLevel;

  /// [level] without a delegated child's request.
  ChatAttentionLevel get ownLevel {
    if (hasPendingRequests || status == AgentChatSessionStatus.waiting) {
      return ChatAttentionLevel.needsInput;
    }
    return switch (status) {
      AgentChatSessionStatus.error => ChatAttentionLevel.failed,
      AgentChatSessionStatus.starting ||
      AgentChatSessionStatus.running => ChatAttentionLevel.working,
      _ when unread => ChatAttentionLevel.unread,
      _ when openChildTaskCount > 0 => ChatAttentionLevel.waitingOnTasks,
      _ => ChatAttentionLevel.idle,
    };
  }

  /// The level a view that also lists this chat's children shows: when a
  /// child that needs input is among them ([parentsWithListedChildInput]),
  /// that child carries the request and the parent reads as waiting on it,
  /// so one request is not counted twice. A child the view does not list
  /// still raises the parent.
  ChatAttentionLevel levelAmong(Set<String> parentsWithListedChildInput) =>
      parentsWithListedChildInput.contains(chatId) ? ownLevel : level;

  /// The entry after [change]: a session change sets the status, a request
  /// list sets whether anything is pending, a title change renames it.
  /// Read state and child counts only change with the next list read.
  ChatAttentionEntry folded(AgentChatChange change, DateTime now) =>
      ChatAttentionEntry(
        chatId: chatId,
        workspaceId: workspaceId,
        title: change.title ?? title,
        updatedAt: change.session == null && change.requests == null
            ? updatedAt
            : now,
        tabId: tabId,
        provider: change.provider ?? provider,
        status: change.session?.status ?? status,
        hasPendingRequests: change.requests == null
            ? hasPendingRequests
            : change.requests!.isNotEmpty,
        openChildTaskCount: openChildTaskCount,
        childNeedsInput: childNeedsInput,
        unread: unread,
        parentChatId: parentChatId,
      );

  /// The entry with child task counts from the live task lists.
  ChatAttentionEntry withChildren(ChatTaskChildren children) =>
      children.open == openChildTaskCount &&
          children.needsInput == childNeedsInput
      ? this
      : ChatAttentionEntry(
          chatId: chatId,
          workspaceId: workspaceId,
          title: title,
          updatedAt: updatedAt,
          tabId: tabId,
          provider: provider,
          status: status,
          hasPendingRequests: hasPendingRequests,
          openChildTaskCount: children.open,
          childNeedsInput: children.needsInput,
          unread: unread,
          parentChatId: parentChatId,
        );

  @override
  bool operator ==(Object other) =>
      other is ChatAttentionEntry &&
      other.chatId == chatId &&
      other.workspaceId == workspaceId &&
      other.title == title &&
      other.updatedAt == updatedAt &&
      other.tabId == tabId &&
      other.provider == provider &&
      other.status == status &&
      other.hasPendingRequests == hasPendingRequests &&
      other.openChildTaskCount == openChildTaskCount &&
      other.childNeedsInput == childNeedsInput &&
      other.unread == unread &&
      other.parentChatId == parentChatId;

  @override
  int get hashCode => Object.hash(
    chatId,
    workspaceId,
    title,
    updatedAt,
    tabId,
    provider,
    status,
    hasPendingRequests,
    openChildTaskCount,
    childNeedsInput,
    unread,
    parentChatId,
  );
}

/// The chats of one workspace that want someone, for its sidebar row.
class const ChatWorkspaceAttention({
  final int needsInput = 0,
  final int failed = 0,
  final int unread = 0,
  final int working = 0,
  final int waitingOnTasks = 0,
  final DateTime? latestAt,
}) {
  ChatAttentionLevel get level => needsInput > 0
      ? ChatAttentionLevel.needsInput
      : failed > 0
      ? ChatAttentionLevel.failed
      : unread > 0
      ? ChatAttentionLevel.unread
      : working > 0
      ? ChatAttentionLevel.working
      : waitingOnTasks > 0
      ? ChatAttentionLevel.waitingOnTasks
      : ChatAttentionLevel.idle;

  /// `2 chats need input · 1 unread result`, for the row tooltip.
  String get description => <String>[
    if (needsInput > 0)
      '$needsInput ${needsInput == 1 ? 'chat needs' : 'chats need'} input',
    if (failed > 0) '$failed ${failed == 1 ? 'chat' : 'chats'} stopped',
    if (unread > 0) '$unread unread ${unread == 1 ? 'result' : 'results'}',
    if (working > 0) '$working ${working == 1 ? 'chat' : 'chats'} working',
    if (waitingOnTasks > 0) '$waitingOnTasks waiting on delegated tasks',
  ].join(' · ');

  @override
  bool operator ==(Object other) =>
      other is ChatWorkspaceAttention &&
      other.needsInput == needsInput &&
      other.failed == failed &&
      other.unread == unread &&
      other.working == working &&
      other.waitingOnTasks == waitingOnTasks &&
      other.latestAt == latestAt;

  @override
  int get hashCode => Object.hash(
    needsInput,
    failed,
    unread,
    working,
    waitingOnTasks,
    latestAt,
  );
}

/// The chats among [entries] that have a child chat, also among [entries],
/// needing input, for [ChatAttentionEntry.levelAmong].
Set<String> chatParentsWithListedChildInput(
  Iterable<ChatAttentionEntry> entries,
) {
  final listed = <String>{for (final entry in entries) entry.chatId};
  return <String>{
    for (final entry in entries)
      if (entry.parentChatId case final parent?
          when parent != entry.chatId &&
              listed.contains(parent) &&
              entry.ownLevel == ChatAttentionLevel.needsInput)
        parent,
  };
}

/// Groups chat entries by workspace, leaving out workspaces whose chats are
/// all idle so the sidebar only marks rows that want someone. A child that
/// needs input in the same workspace counts there instead of on its parent.
Map<String, ChatWorkspaceAttention> chatWorkspaceAttentionOf(
  Iterable<ChatAttentionEntry> entries,
) {
  final byWorkspace = <String, List<ChatAttentionEntry>>{};
  for (final entry in entries) {
    byWorkspace.putIfAbsent(entry.workspaceId, () => []).add(entry);
  }
  final covered = <String>{
    for (final group in byWorkspace.values)
      ...chatParentsWithListedChildInput(group),
  };
  final counts = <String, List<int>>{};
  final latest = <String, DateTime>{};
  for (final entry in entries) {
    final level = entry.levelAmong(covered);
    if (level == ChatAttentionLevel.idle) continue;
    final row = counts.putIfAbsent(
      entry.workspaceId,
      () => List<int>.filled(ChatAttentionLevel.values.length, 0),
    );
    row[level.index] += 1;
    final at = latest[entry.workspaceId];
    if (at == null || entry.updatedAt.isAfter(at)) {
      latest[entry.workspaceId] = entry.updatedAt;
    }
  }
  return Map<String, ChatWorkspaceAttention>.unmodifiableOf(
    <String, ChatWorkspaceAttention>{
      for (final MapEntry(:key, :value) in counts.entries)
        key: ChatWorkspaceAttention(
          needsInput: value[ChatAttentionLevel.needsInput.index],
          failed: value[ChatAttentionLevel.failed.index],
          unread: value[ChatAttentionLevel.unread.index],
          working: value[ChatAttentionLevel.working.index],
          waitingOnTasks: value[ChatAttentionLevel.waitingOnTasks.index],
          latestAt: latest[key],
        ),
    },
  );
}
