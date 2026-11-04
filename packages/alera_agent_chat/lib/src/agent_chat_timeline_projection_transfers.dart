part of 'agent_chat_timeline_projection.dart';

/// Context another chat moved into this one, drawn as its own row (T3 Code's
/// fork and transfer lifecycle rows): "Forked From", "Merged Back From",
/// "Delegated By" or "Result From" the source chat. A merge-back's notice
/// becomes its row, kept as [notice] for the work the fork handed back. A
/// provider handoff stays the divider above its turn and gets no row.
final class AgentChatTransferEntry extends AgentChatTimelineEntry {
  const AgentChatTransferEntry(this.transfer, {this.notice});

  final AgentChatContextTransfer transfer;
  final AgentChatItem? notice;

  @override
  String get key => 'transfer-${transfer.id}';
}

/// Puts each cross-chat transfer of [thread] where it happened: a fork after
/// the turn it was taken through, delegated work before the turn it started,
/// a merge-back in place of its notice, anything else by time. A row whose
/// place is in history not loaded yet waits for that page.
void _insertTransfers(
  List<AgentChatTimelineEntry> entries,
  AgentChatThread thread,
) {
  final complete = thread.historyBefore == null;
  int? turnIndex(String? turnId) {
    if (turnId == null) return null;
    final index = entries.indexWhere(
      (entry) => entry is AgentChatTurnEntry && entry.section.turnId == turnId,
    );
    return index < 0 ? null : index;
  }

  for (final transfer in thread.contextTransfers) {
    if (!transfer.crossChat) continue;
    final row = AgentChatTransferEntry(transfer);
    if (transfer.kind == AgentChatTransferKind.mergeBack &&
        transfer.itemId != null) {
      final index = entries.indexWhere(
        (entry) =>
            entry is AgentChatStandaloneEntry &&
            entry.item.id == transfer.itemId,
      );
      if (index >= 0) {
        final notice = (entries[index] as AgentChatStandaloneEntry).item;
        entries[index] = AgentChatTransferEntry(transfer, notice: notice);
      }
      continue;
    }
    final anchor = switch (transfer.kind) {
      AgentChatTransferKind.fork => switch (turnIndex(transfer.sourceTurnId)) {
        final index? => index + 1,
        null => null,
      },
      AgentChatTransferKind.subagentSpawn ||
      AgentChatTransferKind.subagentResult => turnIndex(transfer.targetTurnId),
      _ => null,
    };
    if (anchor != null) {
      entries.insert(anchor, row);
      continue;
    }
    final later = entries.indexWhere(
      (entry) => _entryTime(entry)?.isAfter(transfer.createdAt) ?? true,
    );
    final index = later < 0 ? entries.length : later;
    // Older than everything loaded: its place is on an earlier page.
    if (index == 0 && !complete) continue;
    entries.insert(index, row);
  }
}

DateTime? _entryTime(AgentChatTimelineEntry entry) => switch (entry) {
  AgentChatTurnEntry(:final section) => section.startedAt,
  AgentChatStandaloneEntry(:final item) => item.createdAt,
  AgentChatTransferEntry(:final transfer) => transfer.createdAt,
  AgentChatOutgoingEntry() => null,
};
