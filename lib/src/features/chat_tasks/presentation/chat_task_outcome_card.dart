import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_status.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// One task a wake reports: how it ended, how long it took and the start of
/// what it returned, with the explicit ways to look closer. Presentational.
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
    final result = task.result?.text.trim();
    final excerpt = failure != null && failure.isNotEmpty
        ? failure
        : result != null && result.isNotEmpty
        ? result
        : null;
    return Container(
      key: ValueKey<String>('chatTaskOutcome:${task.id}'),
      margin: const EdgeInsets.only(top: AleraTokens.space6),
      padding: const EdgeInsets.all(AleraTokens.space8),
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
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  task.displayTitle,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              Text(duration, style: muted),
            ],
          ),
          if (excerpt != null) ...<Widget>[
            const SizedBox(height: AleraTokens.space6),
            Text(
              excerpt,
              maxLines: excerptLines,
              overflow: .ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: failure != null && failure.isNotEmpty
                    ? AleraTokens.error
                    : AleraTokens.foregroundMuted,
              ),
            ),
          ],
          if (onOpenChat != null || onView != null)
            Wrap(
              alignment: .end,
              spacing: AleraTokens.space4,
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
                    child: const Text('View In Activity'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
