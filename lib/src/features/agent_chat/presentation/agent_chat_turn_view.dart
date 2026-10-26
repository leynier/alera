import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_activity_rows.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_find.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_goal_continuation_marker.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_handoff_divider.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_message_views.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_plan_views.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_turn_history.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_turn_parts.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// One turn: the prompt, a header that folds the agent's work, then what the
/// agent answered. While the turn runs its work folds into one live row; a
/// succeeded turn folds it under "Worked for"; a failed, stopped or cancelled
/// turn keeps it open. A steering prompt sits between the work it split, and
/// the work after it folds under its own "Continued for" header. The grammar
/// comes from the shared projection, so the phone shows the same turn.
class const AgentChatTurnView({
  super.key,
  required final AgentChatTurnSection section,
  required final AgentChatTimelineActions actions,
  required final AgentChatExpansion expansion,
  required final String workspacePath,
}) extends StatefulWidget {
  @override
  State<AgentChatTurnView> createState() => _AgentChatTurnViewState();
}

class _AgentChatTurnViewState extends State<AgentChatTurnView> {
  bool _expanded(AgentChatTurnSegment segment) => widget.expansion.isExpanded(
    segment.foldKey,
    byDefault: !segment.collapsedByDefault,
  );

  void _toggle(AgentChatTurnSegment segment) {
    widget.expansion.set(segment.foldKey, expanded: !_expanded(segment));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final history =
        !section.working &&
        section.turn != null &&
        AgentChatTurnHistoryMenu.offers(widget.actions);
    final handoff = section.handoff?.handoff;
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (handoff != null)
            AgentChatHandoffDivider(
              key: ValueKey<String>('agent-chat-handoff-${section.turnId}'),
              handoff: handoff,
            ),
          if (section.goalContinuation)
            AgentChatGoalContinuationMarker(
              key: ValueKey<String>('agent-chat-goal-turn-${section.turnId}'),
            ),
          if (section.backgroundContinuation)
            AgentChatGoalContinuationMarker(
              key: ValueKey<String>(
                'agent-chat-background-turn-${section.turnId}',
              ),
              background: true,
            ),
          for (final prompt in section.prompts)
            _target(
              agentChatFindMessageTargetKey(prompt.id),
              AgentChatUserMessageView(
                chatId: widget.actions.chatId,
                item: prompt,
                workspacePath: widget.workspacePath,
                onOpenFile: widget.actions.onOpenFile,
                expansion: widget.expansion,
              ),
            ),
          for (final segment in section.segments)
            ..._segment(segment, history: history),
          if (!section.working && section.changedFiles.isNotEmpty)
            AgentChatChangedFilesRow(
              turnId: section.turnId,
              changes: section.changedFiles,
              expansion: widget.expansion,
              workspacePath: widget.workspacePath,
              onOpenFile: widget.actions.onOpenFile,
            ),
          if (_turnErrorMessage(section) case final String message)
            AgentChatNoticeRow(
              icon: AleraIcons.warning,
              message: message,
              tone: AgentChatNoticeTone.error,
            ),
        ],
      ),
    );
  }

  /// A segment's steers, its header, its work and its answers. The first
  /// segment's header is the turn header, with the whole turn's time.
  List<Widget> _segment(AgentChatTurnSegment segment, {required bool history}) {
    final section = widget.section;
    final expanded = _expanded(segment);
    final live = segment.liveWork;
    final onToggle = segment.canToggleActivity ? () => _toggle(segment) : null;
    final first = segment.index == 0;
    final showHeader = first
        ? section.working ||
              section.activity.isNotEmpty ||
              section.failed ||
              history
        : segment.live || segment.activity.isNotEmpty;
    return <Widget>[
      for (final steer in segment.steers)
        _target(
          agentChatFindMessageTargetKey(steer.id),
          AgentChatUserMessageView(
            key: ValueKey<String>('agent-chat-steer-${steer.id}'),
            chatId: widget.actions.chatId,
            item: steer,
            workspacePath: widget.workspacePath,
            onOpenFile: widget.actions.onOpenFile,
            expansion: widget.expansion,
            steering: true,
          ),
        ),
      if (showHeader && first)
        AgentChatTurnHeader(
          section: section,
          expanded: expanded,
          onToggle: onToggle,
          trailing: history
              ? AgentChatTurnHistoryMenu(
                  turnId: section.turnId,
                  actions: widget.actions,
                )
              : null,
        )
      else if (showHeader)
        AgentChatTurnSegmentHeader(
          segment: segment,
          expanded: expanded,
          onToggle: onToggle,
        ),
      if (expanded)
        for (final row in segment.activity)
          _target(
            agentChatFindActivityTargetKey(row),
            AgentChatActivityRowView(
              key: ValueKey<String>('agent-chat-activity-${row.key}'),
              row: row,
              expansion: widget.expansion,
              actions: widget.actions,
              workspacePath: widget.workspacePath,
            ),
          )
      else if (live != null) ...<Widget>[
        for (final narration in live.narration)
          AgentChatItemRowView(
            key: ValueKey<String>('agent-chat-narration-${narration.id}'),
            item: narration,
            expansion: widget.expansion,
            actions: widget.actions,
            workspacePath: widget.workspacePath,
          ),
        AgentChatLiveWorkRow(
          key: ValueKey<String>('agent-chat-live-${section.turnId}'),
          live: live,
          onShowEarlier: onToggle,
        ),
      ],
      for (final answer in segment.answers)
        _target(
          agentChatFindAnswerTargetKey(answer.id),
          _AnswerView(
            key: ValueKey<String>('agent-chat-answer-${answer.id}'),
            item: answer,
            actions: widget.actions,
            expansion: widget.expansion,
            workspacePath: widget.workspacePath,
          ),
        ),
    ];
  }

  /// A row find can land on, keyed so rows keep their state as others are
  /// inserted around them.
  static Widget _target(String targetKey, Widget child) => AgentChatFindTarget(
    key: ValueKey<String>('agent-chat-find-$targetKey'),
    targetKey: targetKey,
    child: child,
  );
}

/// The failure a turn ended with, unless an error row already says it.
String? _turnErrorMessage(AgentChatTurnSection section) {
  final turn = section.turn;
  if (turn == null || turn.status != AgentChatTurnStatus.failed) return null;
  if (section.answers.any((item) => item.type == AgentChatItemType.error)) {
    return null;
  }
  return agentChatTurnFailureMessage(turn);
}

class const _AnswerView({
  super.key,
  required final AgentChatItem item,
  required final AgentChatTimelineActions actions,
  required final AgentChatExpansion expansion,
  required final String workspacePath,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return switch (item.type) {
      AgentChatItemType.assistantMessage => AgentChatAssistantMessageView(
        item: item,
        onOpenLink: actions.onOpenLink,
      ),
      AgentChatItemType.plan => AgentChatProposedPlanView(
        item: item,
        expansion: expansion,
        onOpenLink: actions.onOpenLink,
        onImplement: actions.implementablePlanId == item.id
            ? actions.onImplementPlan
            : null,
        onRefine: actions.implementablePlanId == item.id
            ? actions.onRefinePlan
            : null,
      ),
      _ => AgentChatItemRowView(
        item: item,
        expansion: expansion,
        actions: actions,
        workspacePath: workspacePath,
      ),
    };
  }
}
