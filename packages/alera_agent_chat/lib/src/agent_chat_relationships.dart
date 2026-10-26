import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_modes.dart';
import 'package:alera_agent_chat/src/agent_chat_subagent.dart';
import 'package:alera_agent_chat/src/agent_chat_summary.dart';

/// How a related chat or sub-agent relates to the chat on screen.
enum AgentChatRelationKind {
  /// The chat whose delegation handed work to this one.
  parentChat,

  /// The chat this one was forked from: where a merge-back lands.
  forkSource,

  /// A chat this one delegated work to (Chat Tasks).
  delegatedChat,

  /// A chat forked from this one.
  fork,

  /// A provider-native sub-agent of this chat's agent.
  subagent;

  bool get isParent => this == parentChat || this == forkSource;

  String get label => switch (this) {
    parentChat => 'Parent Chat',
    forkSource => 'Forked From',
    delegatedChat => 'Delegated Chat',
    fork => 'Fork',
    subagent => 'Sub-agent',
  };
}

/// One row of the relationships control: a chat to open, or a sub-agent to
/// open in place.
final class const AgentChatRelation({
  required final AgentChatRelationKind kind,
  required final String title,
  required final String statusLabel,
  required final bool active,
  final bool failed = false,

  /// The related chat, for every kind but [AgentChatRelationKind.subagent].
  final String? chatId,

  /// The call that started the sub-agent, for [AgentChatRelationKind.subagent].
  final AgentChatItem? call,

  /// The related chat is not in the list (archived, deleted, or on another
  /// host), so it cannot be opened from here.
  final bool missing = false,
  final DateTime? sortedAt,
}) {
  String get key =>
      call == null ? 'chat-$chatId-${kind.name}' : 'sub-${call!.id}';
}

/// The chat's parent, fork source, delegated chats, forks and native
/// sub-agents, grouped the way T3 Code's lineage panel groups them: related
/// chats first (parents pinned), then agents still working, then previous
/// agents.
final class AgentChatRelationships {
  AgentChatRelationships._(this.related, this.active, this.previous);

  factory AgentChatRelationships.build({
    required String chatId,
    required List<AgentChatSummary> chats,
    Iterable<AgentChatItem> items = const <AgentChatItem>[],
  }) {
    final byId = <String, AgentChatSummary>{
      for (final chat in chats) chat.chatId: chat,
    };
    final current = byId[chatId];
    final related = <AgentChatRelation>[];
    final active = <AgentChatRelation>[];
    final previous = <AgentChatRelation>[];
    AgentChatRelation chatRelation(AgentChatRelationKind kind, String id) {
      final chat = byId[id];
      final working = chat != null && _working(chat);
      return AgentChatRelation(
        kind: kind,
        chatId: id,
        title: _title(chat?.title, fallback: kind.label),
        statusLabel: chat == null ? 'Unavailable' : _chatStatus(chat),
        active: working,
        failed: chat?.status == AgentChatSessionStatus.error,
        missing: chat == null || chat.archived,
        sortedAt: chat?.updatedAt,
      );
    }

    final parent = current?.parentChatId;
    if (parent != null && parent != chatId) {
      related.add(chatRelation(AgentChatRelationKind.parentChat, parent));
    }
    final source = current?.forkedFromChatId;
    if (source != null && source != chatId && source != parent) {
      related.add(chatRelation(AgentChatRelationKind.forkSource, source));
    }
    final forks = <AgentChatRelation>[];
    for (final chat in chats) {
      if (chat.chatId == chatId || chat.archived) continue;
      if (chat.forkedFromChatId == chatId) {
        forks.add(chatRelation(AgentChatRelationKind.fork, chat.chatId));
      } else if (chat.parentChatId == chatId) {
        final relation = chatRelation(
          AgentChatRelationKind.delegatedChat,
          chat.chatId,
        );
        (relation.active ? active : previous).add(relation);
      }
    }
    related.addAll(_newestFirst(forks));
    for (final call in items) {
      if (!call.startsSubagent || call.parentItemId != null) continue;
      final status = call.subagentStatus;
      final relation = AgentChatRelation(
        kind: AgentChatRelationKind.subagent,
        call: call,
        title: _title(call.subagentLabel, fallback: 'Sub-agent'),
        statusLabel: status.label,
        active: status == AgentChatSubagentStatus.running,
        failed: status == AgentChatSubagentStatus.failed,
        sortedAt: call.subagent?.startedAt ?? call.createdAt,
      );
      (relation.active ? active : previous).add(relation);
    }
    return AgentChatRelationships._(
      List<AgentChatRelation>.unmodifiable(related),
      List<AgentChatRelation>.unmodifiable(_newestFirst(active)),
      List<AgentChatRelation>.unmodifiable(_newestFirst(previous)),
    );
  }

  /// Parents (pinned first) and forks.
  final List<AgentChatRelation> related;

  /// Delegated chats and sub-agents still working.
  final List<AgentChatRelation> active;

  /// Delegated chats and sub-agents that settled, folded by default.
  final List<AgentChatRelation> previous;

  bool get isEmpty => related.isEmpty && active.isEmpty && previous.isEmpty;

  int get runningCount => active.length;

  int get failedPreviousCount =>
      previous.where((relation) => relation.failed).length;

  /// The chat a merge-back hands this fork's work to.
  AgentChatRelation? get mergeTarget {
    for (final relation in related) {
      if (relation.kind == AgentChatRelationKind.forkSource) return relation;
    }
    return null;
  }

  /// "Lineage · 2 running", the control's heading.
  String get heading =>
      runningCount == 0 ? 'Lineage' : 'Lineage · $runningCount running';
}

bool _working(AgentChatSummary chat) =>
    chat.busy ||
    chat.status == AgentChatSessionStatus.running ||
    chat.status == AgentChatSessionStatus.waiting ||
    chat.pendingRequestCount > 0;

String _chatStatus(AgentChatSummary chat) {
  if (chat.archived) return 'Archived';
  if (chat.pendingRequestCount > 0) return 'Needs Input';
  if (_working(chat)) return 'Working';
  return switch (chat.status) {
    AgentChatSessionStatus.error => 'Failed',
    AgentChatSessionStatus.starting => 'Starting',
    _ => 'Idle',
  };
}

String _title(String? title, {required String fallback}) {
  final trimmed = title?.trim() ?? '';
  return trimmed.isEmpty ? fallback : trimmed;
}

List<AgentChatRelation> _newestFirst(List<AgentChatRelation> relations) {
  final sorted = List<AgentChatRelation>.of(relations);
  final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  sorted.sort(
    (left, right) =>
        (right.sortedAt ?? epoch).compareTo(left.sortedAt ?? epoch),
  );
  return sorted;
}
