part of 'agent_chat_timeline_projection.dart';

/// The items of one segment before they become rows.
final class _SegmentSlice {
  final List<AgentChatItem> steers = <AgentChatItem>[];
  final List<AgentChatItem> items = <AgentChatItem>[];
}

/// A stretch of a turn's work: the steering prompts that opened it, the work
/// under its header, then what the agent said. The first segment opens with
/// the turn's prompt and folds under the turn header; each later one folds
/// under its own "Continued for" header, so each opens on its own.
final class AgentChatTurnSegment {
  AgentChatTurnSegment._({
    required this.turnId,
    required this.index,
    required this.steers,
    required this.activity,
    required this.answers,
    required this.outcome,
    required this.workedFor,
  });

  factory AgentChatTurnSegment._from({
    required String turnId,
    required int index,
    required _SegmentSlice slice,
    required Map<String, List<AgentChatItem>> subagents,
    required AgentChatTurnOutcome outcome,
  }) {
    final items = slice.items;
    final activityItems = <AgentChatItem>[];
    final answers = <AgentChatItem>[];
    var lastActivity = -1;
    for (var index = 0; index < items.length; index += 1) {
      if (_isActivity(items[index])) lastActivity = index;
    }
    for (var index = 0; index < items.length; index += 1) {
      final item = items[index];
      switch (item.type) {
        case AgentChatItemType.assistantMessage:
          // Text followed by more work is progress narration; the text after
          // the segment's last action is what the agent said.
          (index < lastActivity ? activityItems : answers).add(item);
        case AgentChatItemType.plan || AgentChatItemType.error:
          answers.add(item);
        default:
          activityItems.add(item);
      }
    }
    final start = slice.steers.firstOrNull?.createdAt;
    final end = items.lastOrNull?.updatedAt;
    return AgentChatTurnSegment._(
      turnId: turnId,
      index: index,
      steers: List<AgentChatItem>.unmodifiable(slice.steers),
      activity: List<AgentChatActivityRow>.unmodifiable(
        _activityRows(activityItems, subagents),
      ),
      answers: List<AgentChatItem>.unmodifiable(answers),
      outcome: outcome,
      workedFor:
          outcome == AgentChatTurnOutcome.running ||
              start == null ||
              end == null
          ? null
          : _span(start, end),
    );
  }

  final String turnId;

  /// 0 for the segment the turn's prompt opened.
  final int index;

  /// Steering prompts sent before this segment's work, oldest first. Steers
  /// sent back to back all open the same segment.
  final List<AgentChatItem> steers;
  final List<AgentChatActivityRow> activity;
  final List<AgentChatItem> answers;

  /// How this segment ended: the turn's outcome for the last segment, and
  /// succeeded for one a steer cut off.
  final AgentChatTurnOutcome outcome;

  /// From its first steer to its last item; null for the first segment and
  /// while it runs. The turn header keeps the whole turn's time.
  final Duration? workedFor;

  /// Whether this is the segment a running turn is working in.
  bool get live => outcome == AgentChatTurnOutcome.running;

  String get foldKey => index == 0
      ? agentChatTurnFoldKey(turnId)
      : agentChatTurnSegmentFoldKey(turnId, steers.last.id);

  int get actionCount => _actionCount(activity);

  /// What a running segment shows instead of every action: one row for the
  /// current action. Null once it settles or before it did anything.
  late final AgentChatLiveWork? liveWork = live && activity.isNotEmpty
      ? AgentChatLiveWork._from(activity)
      : null;

  /// Whether the work rows start folded. A running segment folds them into
  /// its live row; a succeeded one folds them unless there is only one; the
  /// last segment of a failed, stopped or cancelled turn keeps them open so
  /// the failing action stays in view.
  bool get collapsedByDefault => switch (outcome) {
    AgentChatTurnOutcome.running => activity.isNotEmpty,
    AgentChatTurnOutcome.succeeded => actionCount > 1,
    _ => false,
  };

  bool get canToggleActivity =>
      live ? (liveWork?.hiddenCount ?? 0) > 0 : actionCount > 1;
}

/// The fold key of a segment a steer opened; [steerId] is its last steer.
String agentChatTurnSegmentFoldKey(String turnId, String steerId) =>
    'turn-$turnId-steer-$steerId';

/// The header of a segment after the first: "Continued for 12s", or
/// "Working" while the turn works in it.
String agentChatTurnSegmentHeaderLabel(AgentChatTurnSegment segment) {
  if (segment.live) return 'Working';
  final duration = segment.workedFor;
  return duration == null
      ? 'Continued'
      : 'Continued for ${agentChatDurationLabel(duration)}';
}

/// "Context Handoff", or that it failed, above a turn that carried the
/// transcript to a fresh provider session.
String agentChatHandoffLabel(AgentChatHandoff handoff) =>
    handoff.failed ? 'Context Handoff Failed' : 'Context Handoff';
