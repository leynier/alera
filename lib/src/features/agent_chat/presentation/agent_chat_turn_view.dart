import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_shimmer_text.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_activity_rows.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_message_views.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_plan_views.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

// A running turn's "Working for" label counts seconds, so it repaints once a
// second and never per frame.
const Duration _elapsedRefresh = Duration(seconds: 1);

/// One turn: the prompt, a "Worked for" divider that folds the agent's work,
/// then what the agent answered.
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
  String get _expansionKey => 'turn-${widget.section.turnId}';

  bool get _expanded => widget.expansion.isExpanded(
    _expansionKey,
    byDefault: !widget.section.collapsedByDefault,
  );

  void _toggle() {
    widget.expansion.set(_expansionKey, expanded: !_expanded);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final expanded = _expanded;
    final showDivider =
        section.working || section.activity.isNotEmpty || section.failed;
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final prompt in section.prompts)
            AgentChatUserMessageView(
              chatId: widget.actions.chatId,
              item: prompt,
              workspacePath: widget.workspacePath,
              onOpenFile: widget.actions.onOpenFile,
            ),
          if (showDivider)
            _WorkedDivider(
              section: section,
              expanded: expanded,
              onToggle: section.canToggleActivity ? _toggle : null,
            ),
          if (expanded)
            for (final row in section.activity)
              AgentChatActivityRowView(
                key: ValueKey<String>('agent-chat-activity-${row.key}'),
                row: row,
                expansion: widget.expansion,
                actions: widget.actions,
                workspacePath: widget.workspacePath,
              ),
          for (final answer in section.answers)
            _AnswerView(
              key: ValueKey<String>('agent-chat-answer-${answer.id}'),
              item: answer,
              section: section,
              actions: widget.actions,
              expansion: widget.expansion,
              workspacePath: widget.workspacePath,
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
}

/// The failure a turn ended with, unless an error row already says it.
String? _turnErrorMessage(AgentChatTurnSection section) {
  final turn = section.turn;
  if (turn == null || turn.status != AgentChatTurnStatus.failed) return null;
  if (section.answers.any((item) => item.type == AgentChatItemType.error)) {
    return null;
  }
  return turn.errorMessage ?? 'The turn failed.';
}

class const _AnswerView({
  super.key,
  required final AgentChatItem item,
  required final AgentChatTurnSection section,
  required final AgentChatTimelineActions actions,
  required final AgentChatExpansion expansion,
  required final String workspacePath,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return switch (item.type) {
      AgentChatItemType.userMessage => AgentChatUserMessageView(
        chatId: actions.chatId,
        item: item,
        workspacePath: workspacePath,
        onOpenFile: actions.onOpenFile,
        steering: true,
      ),
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

class const _WorkedDivider({
  required final AgentChatTurnSection section,
  required final bool expanded,
  required final VoidCallback? onToggle,
}) extends StatefulWidget {
  @override
  State<_WorkedDivider> createState() => _WorkedDividerState();
}

class _WorkedDividerState extends State<_WorkedDivider> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _WorkedDivider oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker() {
    final live = widget.section.working && widget.section.startedAt != null;
    if (live && _ticker == null) {
      _ticker = Timer.periodic(_elapsedRefresh, (_) {
        if (mounted) setState(() {});
      });
    } else if (!live) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  String _label() {
    final section = widget.section;
    final turn = section.turn;
    if (section.working) {
      final startedAt = section.startedAt;
      if (startedAt == null) return 'Working';
      final elapsed = DateTime.now().toUtc().difference(startedAt);
      return 'Working for ${agentChatDurationLabel(elapsed.isNegative ? Duration.zero : elapsed)}';
    }
    final duration = section.workedFor;
    final suffix = duration == null
        ? ''
        : ' after ${agentChatDurationLabel(duration)}';
    return switch (turn?.status) {
      AgentChatTurnStatus.failed => 'Failed$suffix',
      AgentChatTurnStatus.cancelled => 'Cancelled$suffix',
      AgentChatTurnStatus.interrupted when turn!.interruptedByRestart =>
        'Interrupted when the runtime restarted',
      AgentChatTurnStatus.interrupted => 'Stopped$suffix',
      _ =>
        duration == null
            ? 'Worked'
            : 'Worked for ${agentChatDurationLabel(duration)}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final section = widget.section;
    final style = theme.textTheme.bodySmall?.copyWith(
      color: section.failed ? AleraTokens.warning : AleraTokens.foregroundMuted,
    );
    final label = _label();
    final onToggle = widget.onToggle;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space6),
      child: Row(
        children: <Widget>[
          InkWell(
            key: ValueKey<String>('agent-chat-worked-${section.turnId}'),
            onTap: onToggle,
            mouseCursor: onToggle == null
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space6,
                vertical: AleraTokens.space4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (section.working)
                    AleraShimmerText(text: label, style: style)
                  else
                    Text(label, style: style),
                  if (onToggle != null) ...<Widget>[
                    const SizedBox(width: AleraTokens.space4),
                    Icon(
                      widget.expanded
                          ? AleraIcons.chevronDown
                          : AleraIcons.chevronRight,
                      size: AleraTokens.iconMd,
                      color: AleraTokens.foregroundFaint,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          const Expanded(
            child: Divider(
              height: AleraTokens.dividerExtent,
              color: AleraTokens.borderSubtle,
            ),
          ),
        ],
      ),
    );
  }
}
