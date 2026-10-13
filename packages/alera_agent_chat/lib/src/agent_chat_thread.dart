import 'package:alera_agent_chat/src/agent_chat_change.dart';
import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_queue_entry.dart';
import 'package:alera_agent_chat/src/agent_chat_request.dart';
import 'package:alera_agent_chat/src/agent_chat_session.dart';
import 'package:alera_agent_chat/src/agent_chat_snapshot.dart';

sealed class AgentChatApplyOutcome {
  const AgentChatApplyOutcome();
}

final class AgentChatApplied extends AgentChatApplyOutcome {
  const AgentChatApplied(this.thread);

  final AgentChatThread thread;
}

/// The change is for another chat or at or before the local cursor, so it was
/// already reflected (a replay after reconnect, or a duplicate delivery).
final class AgentChatIgnored extends AgentChatApplyOutcome {
  const AgentChatIgnored();
}

/// The change cannot be applied without losing data: a cursor was skipped or
/// a text append does not line up. Only a fresh snapshot recovers.
final class AgentChatGapNeedsSnapshot extends AgentChatApplyOutcome {
  const AgentChatGapNeedsSnapshot(this.reason);

  final String reason;
}

/// The client's copy of one chat, reduced from a snapshot plus every change
/// after it. Immutable: [apply] and [prependHistory] return new threads.
final class AgentChatThread {
  AgentChatThread._(this.snapshot)
    : _itemIndexes = <String, int>{
        for (var index = 0; index < snapshot.items.length; index += 1)
          snapshot.items[index].id: index,
      };

  factory AgentChatThread.fromSnapshot(AgentChatSnapshot snapshot) =>
      AgentChatThread._(
        snapshot.copyWith(
          items: List<AgentChatItem>.unmodifiable(snapshot.items),
          turns: List<AgentChatTurn>.unmodifiable(snapshot.turns),
          pendingRequests: List<AgentChatRequest>.unmodifiable(
            snapshot.pendingRequests,
          ),
          queue: List<AgentChatQueueEntry>.unmodifiable(snapshot.queue),
        ),
      );

  final AgentChatSnapshot snapshot;
  final Map<String, int> _itemIndexes;

  String get chatId => snapshot.chatId;
  String get workspaceId => snapshot.workspaceId;
  int get cursor => snapshot.cursor;
  String? get tabId => snapshot.tabId;
  String get provider => snapshot.provider;
  String get providerInstanceId => snapshot.providerInstanceId;
  String get title => snapshot.title;
  bool get archived => snapshot.archived;
  AgentChatSession get session => snapshot.session;
  List<AgentChatTurn> get turns => snapshot.turns;
  List<AgentChatItem> get items => snapshot.items;
  List<AgentChatRequest> get pendingRequests => snapshot.pendingRequests;
  List<AgentChatQueueEntry> get queue => snapshot.queue;
  AgentChatUsage get usage => snapshot.usage;
  AgentChatRecovery? get recovery => snapshot.recovery;
  String? get historyBefore => snapshot.historyBefore;

  AgentChatItem? itemById(String id) {
    final index = _itemIndexes[id];
    return index == null ? null : items[index];
  }

  AgentChatTurn? turnById(String id) {
    for (final turn in turns.reversed) {
      if (turn.id == id) return turn;
    }
    return null;
  }

  /// Whether the runtime has taken the message: it is in the timeline or in
  /// the queue.
  bool containsClientMessage(String clientMessageId) =>
      items.any((item) => item.clientMessageId == clientMessageId) ||
      queue.any((entry) => entry.clientMessageId == clientMessageId);

  AgentChatApplyOutcome apply(AgentChatChange change) {
    if (change.chatId != chatId || change.cursor <= cursor) {
      return const AgentChatIgnored();
    }
    if (change.cursor != cursor + 1) {
      return AgentChatGapNeedsSnapshot(
        'Expected cursor ${cursor + 1}, received ${change.cursor}.',
      );
    }
    final removed = change.removedItemIds.toSet();
    final next = <AgentChatItem>[
      for (final item in items)
        if (!removed.contains(item.id)) item,
    ];
    final indexes = <String, int>{
      for (var index = 0; index < next.length; index += 1)
        next[index].id: index,
    };
    for (final item in change.items) {
      final index = indexes[item.id];
      if (index == null) {
        indexes[item.id] = next.length;
        next.add(item);
      } else {
        next[index] = item;
      }
    }
    for (final append in change.textAppends) {
      final index = indexes[append.itemId];
      if (index == null) {
        return AgentChatGapNeedsSnapshot(
          'Text append for unknown item ${append.itemId}.',
        );
      }
      final appended = _appendText(next[index], append);
      if (appended == null) {
        return AgentChatGapNeedsSnapshot(
          'Text append for ${append.itemId} does not line up.',
        );
      }
      next[index] = appended;
    }
    return AgentChatApplied(
      AgentChatThread._(
        snapshot.copyWith(
          workspaceId: change.workspaceId.isEmpty ? null : change.workspaceId,
          cursor: change.cursor,
          provider: change.provider,
          providerInstanceId: change.providerInstanceId,
          title: change.title,
          archived: change.archived,
          session: change.session,
          turns: change.turns.isEmpty ? null : _mergeTurns(turns, change.turns),
          items: List<AgentChatItem>.unmodifiable(next),
          pendingRequests: change.requests == null
              ? null
              : List<AgentChatRequest>.unmodifiable(change.requests!),
          queue: change.queue == null
              ? null
              : List<AgentChatQueueEntry>.unmodifiable(change.queue!),
          usage: change.usage,
          recovery: change.hasRecovery ? change.recovery : recovery,
        ),
      ),
    );
  }

  /// Puts an older page in front of the loaded items. Items already present
  /// keep their current version, since the live copy is never older.
  AgentChatThread prependHistory(AgentChatHistoryPage page) {
    final older = <AgentChatItem>[
      for (final item in page.items)
        if (!_itemIndexes.containsKey(item.id)) item,
    ];
    return AgentChatThread._(
      snapshot.copyWith(
        turns: _mergeTurns(page.turns, turns),
        items: List<AgentChatItem>.unmodifiable(<AgentChatItem>[
          ...older,
          ...items,
        ]),
        historyBefore: page.historyBefore,
      ),
    );
  }
}

AgentChatItem? _appendText(AgentChatItem item, AgentChatTextAppend append) {
  final current = switch (append.stream) {
    AgentChatTextStream.text => item.text,
    AgentChatTextStream.reasoningText => item.reasoningText,
    AgentChatTextStream.output => item.output,
  };
  final end = append.offset + append.text.length;
  if (append.offset < 0 || append.offset > current.length) return null;
  // A replay ends inside what is already there; only the part past the
  // current end is new.
  if (end <= current.length) return item;
  final next = current + append.text.substring(current.length - append.offset);
  return switch (append.stream) {
    AgentChatTextStream.text => item.copyWith(text: next),
    AgentChatTextStream.reasoningText => item.copyWith(reasoningText: next),
    AgentChatTextStream.output => item.copyWith(output: next),
  };
}

/// Later lists win per turn id; order follows first appearance.
List<AgentChatTurn> _mergeTurns(
  List<AgentChatTurn> earlier,
  List<AgentChatTurn> later,
) {
  final merged = <String, AgentChatTurn>{
    for (final turn in earlier) turn.id: turn,
  };
  for (final turn in later) {
    merged[turn.id] = turn;
  }
  return List<AgentChatTurn>.unmodifiable(merged.values);
}
