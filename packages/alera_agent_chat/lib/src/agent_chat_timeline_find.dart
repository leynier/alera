import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_timeline_projection.dart';

/// One row of a chat's loaded timeline that holds the find query: a prompt,
/// a steer, an answer, a work row, a standalone notice or an unsent message.
/// Find counts rows rather than occurrences, so each step moves to another
/// row the reader can see highlighted.
final class const AgentChatFindMatch({
  /// The timeline entry the row belongs to.
  required final String entryKey,

  /// The row itself; [agentChatFindTargetKey] and friends build it.
  required final String targetKey,

  /// Folds to open so the row shows, outermost first.
  final List<String> foldKeys = const <String>[],
});

/// The fold key of a proposed plan's full text.
String agentChatPlanFoldKey(String itemId) => 'plan-$itemId';

/// Find target keys, one per kind of row a timeline draws.
String agentChatFindMessageTargetKey(String itemId) => 'message-$itemId';

String agentChatFindAnswerTargetKey(String itemId) => 'answer-$itemId';

String agentChatFindActivityTargetKey(AgentChatActivityRow row) =>
    'activity-${row.key}';

String agentChatFindItemTargetKey(String itemId) => 'item-$itemId';

String agentChatFindOutgoingTargetKey(String clientMessageId) =>
    'outgoing-$clientMessageId';

// Each item's searchable text, lowercased once. Items are immutable and a
// stream replaces only the item that changed, so typing a query or a new
// delta re-reads one item rather than the whole loaded history.
final Expando<String> _searchText = Expando<String>('agentChatFindText');

String _textOf(AgentChatItem item) => _searchText[item] ??= switch (item.type) {
  AgentChatItemType.reasoning || AgentChatItemType.contextCompaction => '',
  AgentChatItemType.userMessage ||
  AgentChatItemType.assistantMessage ||
  AgentChatItemType.plan => item.text,
  _ => <String?>[
    item.title,
    item.toolName,
    item.command,
    item.detail,
    item.text,
  ].whereType<String>().join('\n'),
}.toLowerCase();

/// The rows of [projection] whose text holds [query], ignoring case, in the
/// order the timeline draws them. Only loaded history is searched; earlier
/// pages the reader has not loaded are not part of the projection.
List<AgentChatFindMatch> agentChatFindMatches(
  AgentChatTimelineProjection projection,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return const <AgentChatFindMatch>[];
  final matches = <AgentChatFindMatch>[];
  bool holds(AgentChatItem item) => _textOf(item).contains(needle);
  for (final entry in projection.entries) {
    switch (entry) {
      case AgentChatTurnEntry(:final section):
        _turnMatches(entry.key, section, holds, matches);
      case AgentChatStandaloneEntry(:final item) when holds(item):
        matches.add(
          AgentChatFindMatch(
            entryKey: entry.key,
            targetKey: agentChatFindItemTargetKey(item.id),
          ),
        );
      case AgentChatOutgoingEntry(:final message)
          when message.text.toLowerCase().contains(needle):
        matches.add(
          AgentChatFindMatch(
            entryKey: entry.key,
            targetKey: agentChatFindOutgoingTargetKey(message.clientMessageId),
          ),
        );
      default:
        break;
    }
  }
  return matches;
}

void _turnMatches(
  String entryKey,
  AgentChatTurnSection section,
  bool Function(AgentChatItem item) holds,
  List<AgentChatFindMatch> matches,
) {
  void message(AgentChatItem item) {
    if (!holds(item)) return;
    matches.add(
      AgentChatFindMatch(
        entryKey: entryKey,
        targetKey: agentChatFindMessageTargetKey(item.id),
        foldKeys: <String>[agentChatMessageFoldKey(item.id)],
      ),
    );
  }

  section.prompts.forEach(message);
  for (final segment in section.segments) {
    segment.steers.forEach(message);
    for (final row in segment.activity) {
      if (!_rowHolds(row, holds)) continue;
      matches.add(
        AgentChatFindMatch(
          entryKey: entryKey,
          targetKey: agentChatFindActivityTargetKey(row),
          foldKeys: <String>[
            segment.foldKey,
            if (row case AgentChatActionGroupRow(:final actions)
                when actions.length > 1)
              agentChatActionGroupFoldKey(row),
          ],
        ),
      );
    }
    for (final answer in segment.answers) {
      if (!holds(answer)) continue;
      matches.add(
        AgentChatFindMatch(
          entryKey: entryKey,
          targetKey: agentChatFindAnswerTargetKey(answer.id),
          foldKeys: <String>[
            if (answer.type == AgentChatItemType.plan)
              agentChatPlanFoldKey(answer.id),
          ],
        ),
      );
    }
  }
}

bool _rowHolds(
  AgentChatActivityRow row,
  bool Function(AgentChatItem item) holds,
) => switch (row) {
  AgentChatActionGroupRow(:final actions) => actions.any(
    (action) => holds(action.item),
  ),
  AgentChatItemRow(:final item) => holds(item),
  AgentChatSubagentRow(:final call) => holds(call),
};
