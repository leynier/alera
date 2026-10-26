import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_history_actions.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_partial_text.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_shimmer.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_skill_chips.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A prompt the person sent, right-aligned like the desktop transcript.
/// Input another chat sent, or a wake for finished delegated tasks, reads as
/// a notice instead, so nobody mistakes it for something they typed.
class const AgentChatUserMessage({super.key, required final AgentChatItem item})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final origin = item.origin;
    if (item.isAutomatedInput && origin != null) {
      return _AutomatedInput(item: item, origin: origin);
    }
    return _UserBubble(
      foldKey: agentChatMessageFoldKey(item.id),
      text: item.text,
      partial: item.isPartialContinuation,
      attachmentNames: <String>[
        for (final attachment in item.attachments) attachment.displayName,
      ],
      footer: _MessageActions(
        text: item.text,
        time: item.createdAt,
        rewindTurnId: item.isPartialContinuation ? null : item.turnId,
      ),
    );
  }
}

class const _AutomatedInput({
  required final AgentChatItem item,
  required final AgentChatItemOrigin origin,
}) extends StatefulWidget {
  @override
  State<_AutomatedInput> createState() => _AutomatedInputState();
}

class _AutomatedInputState extends State<_AutomatedInput> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final origin = widget.origin;
    final tasks = origin.taskIds.length;
    final label = switch (origin.kind) {
      AgentChatItemOriginKind.orchestrationWake =>
        tasks == 1
            ? 'A delegated task finished'
            : tasks > 1
            ? '$tasks delegated tasks finished'
            : 'Delegated work finished',
      AgentChatItemOriginKind.subagentWake =>
        tasks > 1 ? '$tasks sub-agents finished' : 'A sub-agent finished',
      _ => 'Message from another chat',
    };
    final item = widget.item;
    final text = item.isPartialContinuation ? item.text : item.text.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: AleraTokens.space12),
      decoration: BoxDecoration(
        color: AleraTokens.surface,
        borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
            onTap: text.isEmpty
                ? null
                : () => setState(() => _expanded = !_expanded),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AleraTokens.minTapTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AleraTokens.space12,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      switch (origin.kind) {
                        AgentChatItemOriginKind.orchestrationWake =>
                          AleraIcons.workspaceChildren,
                        AgentChatItemOriginKind.subagentWake =>
                          AleraIcons.agent,
                        _ => AleraIcons.inbox,
                      },
                      size: AleraTokens.space16,
                      color: AleraTokens.foregroundMuted,
                    ),
                    const SizedBox(width: AleraTokens.space8),
                    Expanded(
                      child: Text(
                        label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AleraTokens.foregroundMuted,
                        ),
                      ),
                    ),
                    if (text.isNotEmpty)
                      Icon(
                        _expanded
                            ? AleraIcons.chevronDown
                            : AleraIcons.chevronRight,
                        size: AleraTokens.space16,
                        color: AleraTokens.foregroundFaint,
                      ),
                  ],
                ),
              ),
            ),
          ),
          // The sender or the finished tasks, with Open Chat and View Task;
          // it hides itself on a runtime without chat tasks.
          if (AgentChatScope.maybeOf(context) case final scope?)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space12,
              ),
              child: ChatTaskOriginNotice(
                origin: origin,
                chatId: scope.chatId,
                hostId: scope.hostId,
              ),
            ),
          if (_expanded && text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AleraTokens.space12,
                0,
                AleraTokens.space12,
                AleraTokens.space12,
              ),
              child: item.isPartialContinuation
                  ? AgentChatPartialText(text: text)
                  : AgentChatMarkdown(text: text),
            ),
          if (item.isPartialContinuation && !_expanded)
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AleraTokens.space12,
                0,
                AleraTokens.space12,
                AleraTokens.space12,
              ),
              child: AgentChatPartialMessageNote(),
            ),
        ],
      ),
    );
  }
}

/// A prompt still on its way to the runtime, or one it refused.
class const AgentChatOutgoingMessageView({
  super.key,
  required final AgentChatOutgoingMessage message,
  required final VoidCallback? onRetry,
  required final VoidCallback? onEdit,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final failed = message.status == AgentChatOutgoingStatus.failed;
    final faint = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: failed ? AleraTokens.error : AleraTokens.foregroundFaint,
    );
    return _UserBubble(
      foldKey: agentChatMessageFoldKey(message.clientMessageId),
      text: message.text,
      attachmentNames: <String>[
        for (final attachment in message.attachments) attachment.displayName,
      ],
      footer: failed
          ? Wrap(
              alignment: .end,
              crossAxisAlignment: .center,
              spacing: AleraTokens.space4,
              children: <Widget>[
                Text(message.error ?? 'Not sent', style: faint),
                TextButton(onPressed: onEdit, child: const Text('Edit')),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            )
          : message.status == AgentChatOutgoingStatus.accepted
          ? Text('Sent', style: faint)
          : AgentChatShimmerText(text: 'Sending', style: faint),
    );
  }
}

/// A sent message, right-aligned. One longer than eight lines or 600
/// characters starts collapsed behind Show Full Message.
class const _UserBubble({
  required final String foldKey,
  required final String text,
  required final List<String> attachmentNames,
  required final Widget footer,
  final bool partial = false,
}) extends StatefulWidget {
  @override
  State<_UserBubble> createState() => _UserBubbleState();
}

class _UserBubbleState extends State<_UserBubble> {
  late bool _expanded = agentChatFoldExpanded(
    context,
    widget.foldKey,
    fallback: false,
  );

  void _toggle() {
    setState(() => _expanded = !_expanded);
    agentChatRememberFold(context, widget.foldKey, expanded: _expanded);
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final collapsible = !widget.partial && agentChatMessageCollapses(text);
    final collapsed = collapsible && !_expanded;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: (constraints.maxWidth * AleraTokens.chatBubbleWidthFactor)
                .clamp(0.0, AleraTokens.chatBubbleMaxWidth),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: AleraTokens.space12),
            child: Column(
              crossAxisAlignment: .end,
              children: <Widget>[
                if (widget.attachmentNames.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AleraTokens.space6),
                    child: Wrap(
                      alignment: .end,
                      spacing: AleraTokens.space6,
                      runSpacing: AleraTokens.space6,
                      children: <Widget>[
                        for (final name in widget.attachmentNames)
                          Chip(
                            avatar: const Icon(
                              AleraIcons.attach,
                              size: AleraTokens.iconSm,
                            ),
                            label: Text(name, overflow: .ellipsis),
                          ),
                      ],
                    ),
                  ),
                if (text.trim().isNotEmpty || widget.partial)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AleraTokens.surfaceVariant,
                      borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AleraTokens.space12),
                      child: widget.partial
                          ? AgentChatPartialText(text: text)
                          : AgentChatUserBubbleText(
                              text: text,
                              collapsed: collapsed,
                            ),
                    ),
                  ),
                if (collapsible)
                  Semantics(
                    button: true,
                    expanded: _expanded,
                    child: TextButton(
                      onPressed: _toggle,
                      child: Text(
                        _expanded
                            ? agentChatShowLessLabel
                            : agentChatShowFullMessageLabel,
                      ),
                    ),
                  ),
                const SizedBox(height: AleraTokens.space4),
                widget.footer,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The agent's answer. While it streams, the text grows in place and a
/// shimmer says the reply is still coming.
class const AgentChatAssistantMessage({
  super.key,
  required final AgentChatItem item,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final streaming = item.isInProgress;
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space12),
      child: Column(
        crossAxisAlignment: .stretch,
        children: <Widget>[
          if (item.isPartialContinuation)
            AgentChatPartialText(text: item.text)
          else if (item.text.trim().isNotEmpty)
            AgentChatMarkdown(text: item.text),
          if (streaming)
            Padding(
              padding: const EdgeInsets.only(top: AleraTokens.space6),
              child: AgentChatShimmerText(text: 'Responding', style: style),
            )
          else if (item.text.trim().isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: _MessageActions(
                text: item.text,
                time: item.createdAt,
                forkTurnId: item.turnId,
              ),
            ),
        ],
      ),
    );
  }
}

enum _HistoryAction { fork, rewind }

/// Copy and time under a message, plus Fork From Here under an answer and
/// Rewind To Here under a prompt where the chat supports them.
class const _MessageActions({
  required final String text,
  final DateTime? time,
  final String? forkTurnId,
  final String? rewindTurnId,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final stamp = time;
    final history = AgentChatHistoryActions.maybeOf(context);
    final fork = forkTurnId == null ? null : history?.onFork;
    final rewind = rewindTurnId == null ? null : history?.onRewind;
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        IconButton(
          tooltip: 'Copy Message',
          visualDensity: .compact,
          onPressed: () => unawaited(_copy(context)),
          icon: const Icon(AleraIcons.copy, size: AleraTokens.space16),
        ),
        if (stamp != null && stamp.millisecondsSinceEpoch > 0)
          Text(
            MaterialLocalizations.of(context)
                .formatTimeOfDay(TimeOfDay.fromDateTime(stamp.toLocal())),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AleraTokens.foregroundFaint),
          ),
        if (fork != null || rewind != null)
          PopupMenuButton<_HistoryAction>(
            tooltip: 'Message Actions',
            icon: const Icon(AleraIcons.more, size: AleraTokens.space16),
            onSelected: (action) {
              if (action == _HistoryAction.fork) {
                fork?.call(forkTurnId!);
              } else {
                rewind?.call(rewindTurnId!);
              }
            },
            itemBuilder: (context) => <PopupMenuEntry<_HistoryAction>>[
              if (fork != null)
                const PopupMenuItem<_HistoryAction>(
                  value: _HistoryAction.fork,
                  height: AleraTokens.minTapTarget,
                  child: Text('Fork From Here'),
                ),
              if (rewind != null)
                const PopupMenuItem<_HistoryAction>(
                  value: _HistoryAction.rewind,
                  height: AleraTokens.minTapTarget,
                  child: Text('Rewind To Here'),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger?.showSnackBar(const SnackBar(content: Text('Message copied')));
  }
}
