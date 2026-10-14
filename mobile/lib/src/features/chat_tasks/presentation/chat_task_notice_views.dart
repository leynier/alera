import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_tiles.dart';
import 'package:flutter/material.dart';

// Presentational pieces a chat embeds for chat orchestration on the phone.
// Every action is a tap; none of them navigates on arrival.

/// A delegated task that waits on a person, above the parent chat's Tasks
/// dock. Answer Here opens the child's requests in place.
class const ChatTaskInputBanner({
  super.key,
  required final AgentChatTask task,
  required final bool answering,
  required final VoidCallback onAnswerHere,
  final VoidCallback? onOpenChat,
  final int otherCount = 0,
  final Widget? requests,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final more = otherCount > 0
        ? ' (and $otherCount more ${otherCount == 1 ? 'task' : 'tasks'})'
        : '';
    return Semantics(
      liveRegion: true,
      child: Container(
        key: ValueKey<String>('chatTaskInputBanner:${task.id}'),
        padding: const EdgeInsets.all(AleraTokens.spaceMd),
        decoration: BoxDecoration(
          color: AleraTokens.surfaceVariant,
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          border: Border.all(color: AleraTokens.warning),
        ),
        child: Column(
          crossAxisAlignment: .stretch,
          mainAxisSize: .min,
          children: <Widget>[
            Row(
              crossAxisAlignment: .start,
              children: <Widget>[
                const Icon(
                  AleraIcons.warning,
                  size: AleraTokens.iconSm,
                  color: AleraTokens.warning,
                ),
                const SizedBox(width: AleraTokens.spaceSm),
                Expanded(
                  child: Text(
                    'Task needs input: ${task.displayTitle}$more',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.spaceSm),
            Wrap(
              spacing: AleraTokens.spaceSm,
              runSpacing: AleraTokens.spaceXs,
              children: <Widget>[
                FilledButton(
                  key: ValueKey<String>('chatTaskAnswerHere:${task.id}'),
                  onPressed: onAnswerHere,
                  child: Text(answering ? 'Hide Requests' : 'Answer Here'),
                ),
                if (onOpenChat != null)
                  OutlinedButton(
                    key: ValueKey<String>('chatTaskBannerOpenChat:${task.id}'),
                    onPressed: onOpenChat,
                    child: const Text('Open Chat'),
                  ),
              ],
            ),
            if (answering && requests != null) ...<Widget>[
              const SizedBox(height: AleraTokens.spaceSm),
              requests!,
            ],
          ],
        ),
      ),
    );
  }
}

/// One task a wake reports: how it ended, how long it took and the start of
/// what it returned.
class const ChatTaskOutcomeCard({
  super.key,
  required final AgentChatTask task,
  required final DateTime now,
  final VoidCallback? onView,
  final VoidCallback? onOpenChat,
}) extends StatelessWidget {
  static const int excerptLines = 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.labelSmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final elapsed = agentChatDurationLabel(agentChatTaskElapsed(task, now));
    final duration = switch (task.status) {
      AgentChatTaskStatus.completed => 'Worked for $elapsed',
      AgentChatTaskStatus.failed => 'Failed after $elapsed',
      AgentChatTaskStatus.cancelled => 'Stopped after $elapsed',
      AgentChatTaskStatus.interrupted => 'Interrupted after $elapsed',
      _ => 'Working for $elapsed',
    };
    final failure = task.failure?.message.trim();
    final failed = failure != null && failure.isNotEmpty;
    final result = task.result?.text.trim();
    final excerpt = failed
        ? failure
        : result != null && result.isNotEmpty
        ? result
        : null;
    return Container(
      key: ValueKey<String>('chatTaskOutcome:${task.id}'),
      margin: const EdgeInsets.only(top: AleraTokens.spaceXs),
      padding: const EdgeInsets.all(AleraTokens.spaceSm),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        children: <Widget>[
          Row(
            children: <Widget>[
              ChatTaskStatusBadge(status: task.status),
              const SizedBox(width: AleraTokens.spaceSm),
              Expanded(
                child: Text(
                  task.displayTitle,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AleraTokens.spaceXs),
          Text(duration, style: muted),
          if (excerpt != null) ...<Widget>[
            const SizedBox(height: AleraTokens.spaceXs),
            Text(
              excerpt,
              maxLines: excerptLines,
              overflow: .ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: failed ? AleraTokens.error : AleraTokens.foregroundMuted,
              ),
            ),
          ],
          Wrap(
            alignment: .end,
            spacing: AleraTokens.spaceXs,
            children: <Widget>[
              if (onOpenChat != null)
                TextButton(
                  key: ValueKey<String>('chatTaskNoticeOpenChat:${task.id}'),
                  onPressed: onOpenChat,
                  child: const Text('Open Chat'),
                ),
              if (onView != null)
                TextButton(
                  key: ValueKey<String>('chatTaskNoticeView:${task.id}'),
                  onPressed: onView,
                  child: const Text('View Task'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Who sent a message into this chat when it was another chat.
class const ChatMessageSenderRow({
  super.key,
  required final String senderTitle,
  final String? senderPlace,
  final VoidCallback? onOpenChat,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => _OriginLine(
    label: <String>['From $senderTitle', ?senderPlace].join(' · '),
    actions: <Widget>[
      if (onOpenChat != null)
        TextButton(
          key: const ValueKey<String>('chatMessageSenderOpenChat'),
          onPressed: onOpenChat,
          child: const Text('Open Chat'),
        ),
    ],
  );
}

/// Where a task brief came from: `Delegated by Planner` with Open Parent,
/// or `Delegated by you`.
class const ChatTaskOriginRow({
  super.key,
  required final String label,
  final VoidCallback? onOpenParent,
  final VoidCallback? onView,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => _OriginLine(
    key: const ValueKey<String>('chatTaskOrigin'),
    label: label,
    actions: <Widget>[
      if (onOpenParent != null)
        TextButton(
          key: const ValueKey<String>('chatTaskOriginOpenParent'),
          onPressed: onOpenParent,
          child: const Text('Open Parent'),
        ),
      if (onView != null)
        TextButton(
          key: const ValueKey<String>('chatTaskOriginView'),
          onPressed: onView,
          child: const Text('View Task'),
        ),
    ],
  );
}

class const _OriginLine({
  super.key,
  required final String label,
  required final List<Widget> actions,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      const Icon(
        AleraIcons.agent,
        size: AleraTokens.iconSm,
        color: AleraTokens.foregroundMuted,
      ),
      const SizedBox(width: AleraTokens.spaceXs),
      Expanded(
        child: Text(
          label,
          maxLines: 2,
          overflow: .ellipsis,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: AleraTokens.foregroundMuted),
        ),
      ),
      ...actions,
    ],
  );
}
