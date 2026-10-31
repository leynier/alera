part of 'agent_chat_timeline_projection.dart';

/// How a turn ended, or that it still runs.
enum AgentChatTurnOutcome {
  running,
  succeeded,
  failed,
  cancelled,

  /// The person or the provider stopped the turn.
  stopped,

  /// The runtime cut the turn short when it restarted.
  interruptedByRestart,
}

AgentChatTurnOutcome _outcomeFor({
  required bool working,
  required AgentChatTurn? turn,
}) {
  if (working) return AgentChatTurnOutcome.running;
  return switch (turn?.status) {
    AgentChatTurnStatus.failed => AgentChatTurnOutcome.failed,
    AgentChatTurnStatus.cancelled => AgentChatTurnOutcome.cancelled,
    AgentChatTurnStatus.interrupted when turn!.interruptedByRestart =>
      AgentChatTurnOutcome.interruptedByRestart,
    AgentChatTurnStatus.interrupted => AgentChatTurnOutcome.stopped,
    _ => AgentChatTurnOutcome.succeeded,
  };
}

/// The one row a running turn shows for its work: the current action in the
/// present tense, the first sentence of the latest reasoning, and how much
/// sits behind the disclosure. Progress narration stays inline above it.
final class AgentChatLiveWork {
  AgentChatLiveWork._({
    required this.label,
    required this.current,
    required this.reasoning,
    required this.earlierCount,
    required this.hiddenCount,
    required this.lastActionFailed,
    required this.narration,
    required this.compaction,
  });

  factory AgentChatLiveWork._from(List<AgentChatActivityRow> activity) {
    final actions = <AgentChatWorkedAction>[];
    final narration = <AgentChatItem>[];
    AgentChatItem? reasoning;
    AgentChatItem? compaction;
    var lastActionRow = -1;
    var lastReasoningRow = -1;
    var otherItems = 0;
    for (final (index, row) in activity.indexed) {
      switch (row) {
        case AgentChatActionGroupRow(actions: final group):
          actions.addAll(group);
          lastActionRow = index;
        case AgentChatSubagentRow(:final call):
          actions.add(AgentChatWorkedAction.fromItem(call));
          lastActionRow = index;
        case AgentChatItemRow(:final item)
            when item.type == AgentChatItemType.assistantMessage:
          narration.add(item);
        case AgentChatItemRow(:final item)
            when item.type == AgentChatItemType.reasoning:
          if (reasoning != null) otherItems += 1;
          reasoning = item;
          lastReasoningRow = index;
        // The live row shows a running compaction, so it is not hidden.
        case AgentChatItemRow(:final item)
            when item.type == AgentChatItemType.contextCompaction &&
                item.isInProgress:
          if (compaction != null) otherItems += 1;
          compaction = item;
        case AgentChatItemRow():
          otherItems += 1;
      }
    }
    final last = actions.lastOrNull;
    final lastFailed = last?.item.isFailed ?? false;
    // A failed action is not what the agent is doing now, and reasoning
    // after a finished action means it moved on to thinking.
    final thinkingAfter =
        last != null &&
        !last.item.isInProgress &&
        lastReasoningRow > lastActionRow &&
        (reasoning?.isInProgress ?? false);
    final current = compaction != null || lastFailed || thinkingAfter
        ? null
        : last;
    final reasoningText = reasoning == null
        ? ''
        : reasoning.reasoningText.trim().isNotEmpty
        ? reasoning.reasoningText
        : reasoning.text;
    // Reasoning from before a compaction is stale while it runs.
    final snippet = compaction != null
        ? null
        : agentChatReasoningSnippet(reasoningText);
    final reasoningHidden =
        reasoning != null &&
        (compaction != null || reasoningText.trim() != (snippet ?? ''));
    final earlier = actions.length - (current == null ? 0 : 1);
    return AgentChatLiveWork._(
      label: compaction != null
          ? 'Compacting'
          : switch (current) {
              null => 'Thinking',
              final AgentChatWorkedAction action
                  when action.item.isInProgress =>
                agentChatWorkedActionLiveLabel(action),
              final AgentChatWorkedAction action => action.label,
            },
      current: current,
      reasoning: snippet,
      earlierCount: earlier,
      hiddenCount: earlier + otherItems + (reasoningHidden ? 1 : 0),
      lastActionFailed: lastFailed,
      narration: List<AgentChatItem>.unmodifiable(narration),
      compaction: compaction,
    );
  }

  /// "Running make test", "Reading main.dart", or "Thinking" when there is
  /// no action yet, the last one failed, or the agent went back to thinking.
  /// While [compacting] it reads "Compacting"; apps that keep a clock show
  /// [agentChatCompactingLabel] instead.
  final String label;

  /// The action [label] describes; null when it reads "Thinking" or while
  /// the agent compacts its context.
  final AgentChatWorkedAction? current;

  /// The first sentence of the latest reasoning, clamped.
  final String? reasoning;

  /// Actions behind the disclosure, a failed last action included.
  final int earlierCount;

  /// Everything the disclosure reveals that the live row does not show:
  /// [earlierCount] plus earlier reasoning, notices and compaction.
  final int hiddenCount;
  final bool lastActionFailed;

  /// Progress narration, in order; it stays visible above the live row.
  final List<AgentChatItem> narration;

  /// A context compaction the agent is running now. While it runs the live
  /// row is the compaction, timed from when it started.
  final AgentChatItem? compaction;

  bool get compacting => compaction != null;

  /// When the running compaction started; the live row times it from here.
  DateTime? get compactingSince => compaction?.createdAt;

  /// "3 earlier actions", or null when there are none.
  String? get earlierLabel => switch (earlierCount) {
    0 => null,
    1 => '1 earlier action',
    final count => '$count earlier actions',
  };
}

List<AgentChatFileChange> _changedFiles(List<AgentChatItem> items) {
  final byPath = <String, AgentChatFileChange>{};
  for (final item in items) {
    if (item.type != AgentChatItemType.fileChange || item.isFailed) continue;
    for (final change in item.changes) {
      if (change.path.isEmpty) continue;
      // Re-inserting moves the path to the end, so the list reads in the
      // order the files were last touched.
      byPath
        ..remove(change.path)
        ..[change.path] = change;
    }
  }
  return List<AgentChatFileChange>.unmodifiable(byPath.values);
}

/// "Changed Files (3)".
String agentChatChangedFilesLabel(int count) => 'Changed Files ($count)';

/// The label of a turn's "Worked for" header. [now] drives the live
/// "Working for" counter of a running turn.
String agentChatTurnHeaderLabel(
  AgentChatTurnSection section, {
  required DateTime now,
}) {
  final duration = section.workedFor;
  final suffix = duration == null
      ? ''
      : ' after ${agentChatDurationLabel(duration)}';
  final startedAt = section.startedAt;
  return switch (section.outcome) {
    AgentChatTurnOutcome.running when startedAt == null => 'Working',
    AgentChatTurnOutcome.running =>
      'Working for ${agentChatDurationLabel(_elapsed(startedAt!, now))}',
    AgentChatTurnOutcome.succeeded =>
      duration == null
          ? 'Worked'
          : 'Worked for ${agentChatDurationLabel(duration)}',
    AgentChatTurnOutcome.failed => 'Failed$suffix',
    AgentChatTurnOutcome.cancelled => 'Cancelled$suffix',
    AgentChatTurnOutcome.stopped => 'Stopped$suffix',
    AgentChatTurnOutcome.interruptedByRestart =>
      'Interrupted when the runtime restarted',
  };
}

/// The live row of a running compaction: "Compacting for 12s", timed from
/// [since], or "Compacting" when its start is unknown.
String agentChatCompactingLabel(DateTime? since, {required DateTime now}) =>
    since == null
    ? 'Compacting'
    : 'Compacting for ${agentChatDurationLabel(_elapsed(since, now))}';

/// The row of a context compaction item: "Compacting context" while it
/// runs, "Compacted context (1.5k → 400 tokens)" once done, and why it ended
/// otherwise. A stopped compaction arrives as failed with
/// `data.outcome: stopped`, since items have no interrupted status.
String agentChatCompactionLabel(AgentChatItem item) {
  if (item.isInProgress) return 'Compacting context';
  if (item.isFailed) {
    return agentChatWireToken(item.data['outcome']) == 'stopped'
        ? 'Compaction stopped'
        : 'Compaction failed';
  }
  final before = agentChatJsonInt(item.data['preTokens']);
  final after = agentChatJsonInt(item.data['postTokens']);
  if (before == null || after == null) return 'Compacted context';
  return 'Compacted context (${agentChatContextTokenLabel(before)} → '
      '${agentChatContextTokenLabel(after)} tokens)';
}

/// "400", "1.5k", "120k", "1.2m": a token count at a glance, as T3 Code
/// writes context sizes.
String agentChatContextTokenLabel(int tokens) {
  String trim(String value) =>
      value.endsWith('.0') ? value.substring(0, value.length - 2) : value;
  if (tokens < 1000) return '$tokens';
  if (tokens < 10000) return '${trim((tokens / 1000).toStringAsFixed(1))}k';
  if (tokens < 999500) return '${(tokens / 1000).round()}k';
  return '${trim((tokens / 1000000).toStringAsFixed(1))}m';
}

Duration _elapsed(DateTime start, DateTime now) {
  final elapsed = now.toUtc().difference(start.toUtc());
  return elapsed.isNegative ? Duration.zero : elapsed;
}

/// Keys of the collapsible parts of a timeline. Both apps keep the person's
/// fold overrides per chat under these keys; a part without an override
/// follows its default. One turn key covers both the running disclosure and
/// the settled "Worked for" fold, so what was opened while the turn ran stays
/// open after it settles.
String agentChatTurnFoldKey(String turnId) => 'turn-$turnId';

String agentChatActionGroupFoldKey(AgentChatActionGroupRow row) => row.key;

String agentChatActionFoldKey(String itemId) => 'action-$itemId';

String agentChatReasoningFoldKey(String itemId) => 'reasoning-$itemId';

String agentChatMessageFoldKey(String itemId) => 'message-$itemId';

String agentChatChangedFilesFoldKey(String turnId) => 'changes-$turnId';

/// A message longer than this many lines starts collapsed.
const int agentChatMessageCollapseLines = 8;

/// A message longer than this many characters starts collapsed.
const int agentChatMessageCollapseCharacters = 600;

const String agentChatShowFullMessageLabel = 'Show Full Message';

const String agentChatShowLessLabel = 'Show Less';

/// Whether a sent message starts collapsed behind [agentChatShowFullMessageLabel].
bool agentChatMessageCollapses(String text) {
  final trimmed = text.trimRight();
  if (trimmed.length > agentChatMessageCollapseCharacters) return true;
  return '\n'.allMatches(trimmed).length >= agentChatMessageCollapseLines;
}

const String agentChatScrollToEndDefaultLabel = 'Scroll To End';

/// The label of the pill that returns a scrolled-up timeline to its end. It
/// names a pending request, because requests dock under the timeline and a
/// reader scrolled up may not see the dock change.
String agentChatScrollToEndLabel(List<AgentChatRequest> requests) {
  if (requests.any((request) => request.isApproval)) return 'Approval Needed';
  if (requests.isNotEmpty) return 'Input Needed';
  return agentChatScrollToEndDefaultLabel;
}
