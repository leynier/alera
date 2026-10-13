import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_status.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

/// One task inside a chat: its status, title and the explicit ways to look
/// closer. Presentational, so the timeline embed and previews share it.
class const ChatTaskNoticeRow({
  super.key,
  required final AgentChatTask task,
  final VoidCallback? onView,
  final VoidCallback? onOpenChat,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space4),
      child: Row(
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        const Icon(
          AleraIcons.agent,
          size: AleraTokens.iconSm,
          color: AleraTokens.foregroundMuted,
        ),
        const SizedBox(width: AleraTokens.space6),
        Expanded(
          child: Text(
            <String>['From $senderTitle', ?senderPlace].join(' · '),
            maxLines: 1,
            overflow: .ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ),
        if (onOpenChat != null)
          TextButton(
            key: const ValueKey<String>('chatMessageSenderOpenChat'),
            onPressed: onOpenChat,
            child: const Text('Open Chat'),
          ),
      ],
    );
  }
}

/// The tasks a chat delegated that still run or need someone, above its
/// composer.
class const ChatTaskDockView({
  super.key,
  required final List<AgentChatTask> tasks,
  required final ValueChanged<AgentChatTask> onView,
  final int total = 0,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final more = total - tasks.length;
    return Container(
      key: const ValueKey<String>('chatTaskDock'),
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space6,
      ),
      decoration: BoxDecoration(
        color: AleraTokens.surfaceVariant,
        borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
        border: Border.all(color: AleraTokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: .stretch,
        mainAxisSize: .min,
        children: <Widget>[
          Text(
            'Delegated Tasks',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          for (final task in tasks)
            ChatTaskNoticeRow(task: task, onView: () => onView(task)),
          if (more > 0)
            Text(
              '$more more in Activity',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
        ],
      ),
    );
  }
}
