import 'package:alera_agent_chat/src/agent_chat_continuation_projection.dart';
import 'package:alera_agent_chat/src/agent_chat_item.dart';
import 'package:alera_agent_chat/src/agent_chat_json.dart';
import 'package:alera_agent_chat/src/agent_chat_lifecycle_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_modes.dart';
import 'package:alera_agent_chat/src/agent_chat_native_history_inputs.dart';
import 'package:alera_agent_chat/src/agent_chat_native_operation.dart';
import 'package:alera_agent_chat/src/agent_chat_outgoing_message.dart';
import 'package:alera_agent_chat/src/agent_chat_request.dart';
import 'package:alera_agent_chat/src/agent_chat_request_labels.dart';
import 'package:alera_agent_chat/src/agent_chat_session.dart';
import 'package:alera_agent_chat/src/agent_chat_subagent.dart';
import 'package:alera_agent_chat/src/agent_chat_thread.dart';
import 'package:alera_agent_chat/src/agent_chat_worked_actions.dart';

part 'agent_chat_timeline_projection_history.dart';
part 'agent_chat_timeline_projection_subagents.dart';
part 'agent_chat_timeline_projection_turn.dart';

/// A row under a turn's "Worked for" divider.
sealed class AgentChatActivityRow {
  const AgentChatActivityRow();

  String get key;
}

/// Consecutive tool, command and file actions folded into one summary line.
final class AgentChatActionGroupRow extends AgentChatActivityRow {
  AgentChatActionGroupRow(this.actions)
    : summary = agentChatWorkedSummary(actions),
      streaming = actions.any((action) => action.item.isInProgress);

  final List<AgentChatWorkedAction> actions;
  final String summary;
  final bool streaming;

  @override
  String get key => 'actions-${actions.first.item.id}';

  bool get failed => actions.any((action) => action.item.isFailed);
}

/// Reasoning, progress messages, notices and compaction, one row each.
final class AgentChatItemRow extends AgentChatActivityRow {
  const AgentChatItemRow(this.item);

  final AgentChatItem item;

  @override
  String get key => 'item-${item.id}';
}

/// One turn: the prompt, the work under "Worked for", then what the agent
/// said. Sections are reused while their items are unchanged, so a stream of
/// changes to the live turn leaves earlier turns' widgets untouched. Both
/// apps read the turn grammar (live row, folding, header label) from here so
/// they show a turn the same way.
final class AgentChatTurnSection {
  AgentChatTurnSection._({
    required this.turnId,
    required this.turn,
    required this.working,
    required this.prompts,
    required this.activity,
    required this.answers,
    required this.planSteps,
    required this.startedAt,
    required this.workedFor,
    required this.sourceItems,
  });

  factory AgentChatTurnSection.fromItems(
    String turnId,
    List<AgentChatItem> items, {
    required AgentChatTurn? turn,
    required bool working,
  }) {
    final prompts = <AgentChatItem>[];
    final answers = <AgentChatItem>[];
    final activityItems = <AgentChatItem>[];
    AgentChatItem? planSteps;
    // A sub-agent's own items, text included, belong under its call rather
    // than in the main agent's work or answer.
    final subagents = _subagentChildren(items);
    final childIds = <String>{
      for (final children in subagents.values)
        for (final child in children) child.id,
    };
    var lastActivity = -1;
    for (var index = 0; index < items.length; index += 1) {
      if (!childIds.contains(items[index].id) && _isActivity(items[index])) {
        lastActivity = index;
      }
    }
    for (var index = 0; index < items.length; index += 1) {
      final item = items[index];
      if (childIds.contains(item.id)) continue;
      switch (item.type) {
        case AgentChatItemType.userMessage:
          // The first prompt opens the turn; later ones steered it and stay
          // visible in order with the answers.
          (prompts.isEmpty && answers.isEmpty ? prompts : answers).add(item);
        case AgentChatItemType.assistantMessage:
          // Text followed by more work is progress narration; the text after
          // the last action is the answer.
          (index < lastActivity ? activityItems : answers).add(item);
        case AgentChatItemType.plan when item.planSteps.isNotEmpty:
          planSteps = item;
        case AgentChatItemType.plan || AgentChatItemType.error:
          answers.add(item);
        default:
          activityItems.add(item);
      }
    }
    return AgentChatTurnSection._(
      turnId: turnId,
      turn: turn,
      working: working,
      prompts: List<AgentChatItem>.unmodifiable(prompts),
      activity: List<AgentChatActivityRow>.unmodifiable(
        _activityRows(activityItems, subagents),
      ),
      answers: List<AgentChatItem>.unmodifiable(answers),
      planSteps: planSteps,
      startedAt: turn?.startedAt ?? items.firstOrNull?.createdAt,
      workedFor:
          turn?.duration ??
          (working || items.isEmpty
              ? null
              : _span(items.first.createdAt, items.last.updatedAt)),
      sourceItems: List<AgentChatItem>.unmodifiable(items),
    );
  }

  static AgentChatTurnSection reuseOrCreate(
    AgentChatTurnSection? previous,
    String turnId,
    List<AgentChatItem> items, {
    required AgentChatTurn? turn,
    required bool working,
  }) {
    if (previous != null &&
        previous.working == working &&
        identical(previous.turn, turn) &&
        _sameItems(previous.sourceItems, items)) {
      return previous;
    }
    return AgentChatTurnSection.fromItems(
      turnId,
      items,
      turn: turn,
      working: working,
    );
  }

  final String turnId;
  final AgentChatTurn? turn;
  final bool working;
  final List<AgentChatItem> prompts;
  final List<AgentChatActivityRow> activity;
  final List<AgentChatItem> answers;

  /// The turn's latest plan checklist, shown as progress rather than a row.
  final AgentChatItem? planSteps;

  /// When the turn began; a live "Working for" counter ticks from here.
  final DateTime? startedAt;

  /// How long a finished turn worked.
  final Duration? workedFor;
  final List<AgentChatItem> sourceItems;

  int get actionCount => activity.fold<int>(
    0,
    (count, row) => switch (row) {
      AgentChatActionGroupRow(:final actions) => count + actions.length,
      AgentChatItemRow() || AgentChatSubagentRow() => count + 1,
    },
  );

  /// How the turn ended, or that it still runs.
  late final AgentChatTurnOutcome outcome = _outcomeOf(this);

  /// What a running turn shows instead of every action: one row for the
  /// current action. Null once the turn settles or before it did anything.
  late final AgentChatLiveWork? liveWork = working && activity.isNotEmpty
      ? AgentChatLiveWork._from(activity)
      : null;

  /// Files the turn changed, one entry per path with its latest change.
  late final List<AgentChatFileChange> changedFiles = _changedFiles(
    sourceItems,
  );

  /// Whether the work rows start folded. A running turn folds them into its
  /// live row; a succeeded turn folds them under "Worked for" unless there is
  /// only one; a failed, stopped or cancelled turn keeps them open so the
  /// failing action stays in view.
  bool get collapsedByDefault => switch (outcome) {
    AgentChatTurnOutcome.running => activity.isNotEmpty,
    AgentChatTurnOutcome.succeeded => actionCount > 1,
    _ => false,
  };

  bool get canToggleActivity =>
      working ? (liveWork?.hiddenCount ?? 0) > 0 : actionCount > 1;

  bool get failed => switch (outcome) {
    AgentChatTurnOutcome.running || AgentChatTurnOutcome.succeeded => false,
    _ => true,
  };
}

bool _isActivity(AgentChatItem item) =>
    item.type.isActivity ||
    item.type == AgentChatItemType.reasoning ||
    item.type == AgentChatItemType.contextCompaction ||
    item.type == AgentChatItemType.notice;

List<AgentChatActivityRow> _activityRows(
  List<AgentChatItem> items, [
  Map<String, List<AgentChatItem>> subagents =
      const <String, List<AgentChatItem>>{},
]) {
  final rows = <AgentChatActivityRow>[];
  var group = <AgentChatWorkedAction>[];
  void flush() {
    if (group.isEmpty) return;
    rows.add(AgentChatActionGroupRow(List.unmodifiable(group)));
    group = <AgentChatWorkedAction>[];
  }

  for (final item in items) {
    if (item.startsSubagent) {
      flush();
      rows.add(
        AgentChatSubagentRow(
          item,
          _activityRows(subagents[item.id] ?? const <AgentChatItem>[]),
          childCount: subagents[item.id]?.length ?? 0,
        ),
      );
    } else if (item.type.isActivity && item.type != AgentChatItemType.unknown) {
      group.add(AgentChatWorkedAction.fromItem(item));
    } else {
      flush();
      rows.add(AgentChatItemRow(item));
    }
  }
  flush();
  return rows;
}

Duration? _span(DateTime start, DateTime end) =>
    end.isBefore(start) ? null : end.difference(start);

/// Whether [next] holds exactly the request objects of [previous], in any
/// order: the dock order is derived, so only membership matters.
bool _sameRequests(
  List<AgentChatRequest> previous,
  List<AgentChatRequest> next,
) {
  if (previous.length != next.length) return false;
  for (final request in next) {
    if (!previous.any((candidate) => identical(candidate, request))) {
      return false;
    }
  }
  return true;
}

bool _sameItems(List<AgentChatItem> previous, List<AgentChatItem> next) {
  if (previous.length != next.length) return false;
  for (var index = 0; index < previous.length; index += 1) {
    if (!identical(previous[index], next[index])) return false;
  }
  return true;
}

sealed class AgentChatTimelineEntry {
  const AgentChatTimelineEntry();

  String get key;
}

final class AgentChatTurnEntry extends AgentChatTimelineEntry {
  const AgentChatTurnEntry(this.section);

  final AgentChatTurnSection section;

  @override
  String get key => 'turn-${section.turnId}';
}

/// An item outside any turn: chat-level notices, errors and compaction.
final class AgentChatStandaloneEntry extends AgentChatTimelineEntry {
  const AgentChatStandaloneEntry(this.item);

  final AgentChatItem item;

  @override
  String get key => 'item-${item.id}';
}

/// A message the user sent that the runtime has not stamped into the
/// timeline yet, or that it rejected.
final class AgentChatOutgoingEntry extends AgentChatTimelineEntry {
  const AgentChatOutgoingEntry(this.message);

  final AgentChatOutgoingMessage message;

  @override
  String get key => 'outgoing-${message.clientMessageId}';
}

/// The timeline both apps render, derived from a thread.
final class AgentChatTimelineProjection {
  AgentChatTimelineProjection._(
    this.entries,
    this.requests,
    this._sections,
    this._continuations,
  ) : _indexes = <String, int>{
        for (var index = 0; index < entries.length; index += 1)
          entries[index].key: index,
      };

  factory AgentChatTimelineProjection.build(
    AgentChatThread thread, {
    List<AgentChatOutgoingMessage> outgoing =
        const <AgentChatOutgoingMessage>[],
    AgentChatTimelineProjection? previous,
  }) {
    final grouped = <String, List<AgentChatItem>>{};
    final order = <Object>[];
    final continuations = AgentChatContinuationProjection.build(
      thread.items,
      previous: previous?._continuations,
    );
    for (final item in continuations.items) {
      final turnId = item.turnId;
      if (turnId == null) {
        order.add(item);
        continue;
      }
      final existing = grouped[turnId];
      if (existing == null) {
        grouped[turnId] = <AgentChatItem>[item];
        order.add(turnId);
      } else {
        existing.add(item);
      }
    }
    final activeTurnId = thread.session.activeTurnId;
    final sections = <String, AgentChatTurnSection>{};
    final entries = <AgentChatTimelineEntry>[];
    for (final element in order) {
      if (element is AgentChatItem) {
        entries.add(AgentChatStandaloneEntry(element));
        continue;
      }
      final turnId = element as String;
      final turn = thread.turnById(turnId);
      final section = AgentChatTurnSection.reuseOrCreate(
        previous?._sections[turnId],
        turnId,
        grouped[turnId]!,
        turn: turn,
        working:
            turnId == activeTurnId ||
            turn?.status == AgentChatTurnStatus.running,
      );
      sections[turnId] = section;
      entries.add(AgentChatTurnEntry(section));
    }
    for (final message in outgoing) {
      if (!thread.containsClientMessage(message.clientMessageId)) {
        entries.add(AgentChatOutgoingEntry(message));
      }
    }
    final previousRequests = previous?.requests;
    return AgentChatTimelineProjection._(
      List<AgentChatTimelineEntry>.unmodifiable(entries),
      previousRequests != null &&
              _sameRequests(previousRequests, thread.pendingRequests)
          ? previousRequests
          : agentChatRequestDockOrder(thread.pendingRequests),
      sections,
      continuations,
    );
  }

  final List<AgentChatTimelineEntry> entries;

  /// Every pending request, in the order the request dock pages through
  /// them: approvals, then MCP forms, then the rest, oldest first within
  /// each. Requests are not timeline entries; both apps dock them above the
  /// composer. The list is reused while the requests are unchanged, so the
  /// dock rebuilds only when one arrives or resolves.
  final List<AgentChatRequest> requests;
  final Map<String, AgentChatTurnSection> _sections;
  final AgentChatContinuationProjection _continuations;
  final Map<String, int> _indexes;

  /// Pending questions, in dock order.
  List<AgentChatRequest> get questions => <AgentChatRequest>[
    for (final request in requests)
      if (request.isQuestion) request,
  ];

  bool get isEmpty => entries.isEmpty && requests.isEmpty;

  int? indexOfKey(String key) => _indexes[key];

  AgentChatTurnSection? sectionFor(String turnId) => _sections[turnId];

  /// The newest plan checklist of the chat, if its turn is still the latest.
  AgentChatItem? get activePlanSteps {
    for (final entry in entries.reversed) {
      if (entry is AgentChatTurnEntry) return entry.section.planSteps;
    }
    return null;
  }

  /// Prompts the person sent, oldest first, for composer history recall.
  /// Messages from other chats and orchestration wakes are not theirs.
  List<String> get promptHistory => <String>[
    for (final entry in entries)
      if (entry is AgentChatTurnEntry)
        for (final prompt in entry.section.prompts)
          if (!prompt.isAutomatedInput &&
              !prompt.isPartialContinuation &&
              prompt.text.trim().isNotEmpty)
            prompt.text.trim(),
  ];
}
