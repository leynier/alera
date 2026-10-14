import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_activity_rows.dart';
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
/// turn keeps it open. The grammar comes from the shared projection, so the
/// phone shows the same turn.
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
  String get _foldKey => agentChatTurnFoldKey(widget.section.turnId);

  bool get _expanded => widget.expansion.isExpanded(
    _foldKey,
    byDefault: !widget.section.collapsedByDefault,
  );

  void _toggle() {
    widget.expansion.set(_foldKey, expanded: !_expanded);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final expanded = _expanded;
    final live = section.liveWork;
    final history =
        !section.working &&
        section.turn != null &&
        AgentChatTurnHistoryMenu.offers(widget.actions);
    final showHeader =
        section.working ||
        section.activity.isNotEmpty ||
        section.failed ||
        history;
    final onToggle = section.canToggleActivity ? _toggle : null;
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
              expansion: widget.expansion,
            ),
          if (showHeader)
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
            ),
          if (expanded)
            for (final row in section.activity)
              AgentChatActivityRowView(
                key: ValueKey<String>('agent-chat-activity-${row.key}'),
                row: row,
                expansion: widget.expansion,
                actions: widget.actions,
                workspacePath: widget.workspacePath,
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
          for (final answer in section.answers)
            _AnswerView(
              key: ValueKey<String>('agent-chat-answer-${answer.id}'),
              item: answer,
              actions: widget.actions,
              expansion: widget.expansion,
              workspacePath: widget.workspacePath,
            ),
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
        expansion: expansion,
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
