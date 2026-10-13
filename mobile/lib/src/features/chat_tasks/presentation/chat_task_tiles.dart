import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_provider_identity.dart';
import 'package:flutter/material.dart';

AleraBadgeTone chatTaskStatusTone(AgentChatTaskStatus status) =>
    switch (status) {
      AgentChatTaskStatus.preparing => AleraBadgeTone.neutral,
      AgentChatTaskStatus.running => AleraBadgeTone.info,
      AgentChatTaskStatus.needsInput => AleraBadgeTone.attention,
      AgentChatTaskStatus.completed => AleraBadgeTone.success,
      AgentChatTaskStatus.failed => AleraBadgeTone.error,
      AgentChatTaskStatus.interrupted => AleraBadgeTone.attention,
      AgentChatTaskStatus.cancelRequested => AleraBadgeTone.attention,
      AgentChatTaskStatus.cancelled => AleraBadgeTone.neutral,
    };

class const ChatTaskStatusBadge({
  super.key,
  required final AgentChatTaskStatus status,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => AleraBadge(
    label: agentChatTaskStatusLabel(status),
    tone: chatTaskStatusTone(status),
    dot: !status.settled,
  );
}

/// `Codex · gpt-5`: the agent of the task's child chat.
String chatTaskAgentLabel(AgentChatTask task) {
  final provider = task.provider;
  final name = provider == null ? null : agentChatProviderName(provider);
  return <String>[
    if (name != null) name == 'the agent' ? provider! : name,
    ?task.model,
  ].join(' · ');
}

/// A task row: title, status and why it needs attention, where it runs.
class const ChatTaskTile({
  super.key,
  required final AgentChatTask task,
  required final String place,
  required final DateTime now,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = <String>[
      ?agentChatTaskAttentionLabel(task),
      if (chatTaskAgentLabel(task) case final agent when agent.isNotEmpty)
        agent,
      place,
    ].join(' · ');
    return ListTile(
      key: ValueKey<String>('chatTask:${task.id}'),
      minTileHeight: AleraTokens.minTapTarget,
      title: Text(task.displayTitle, maxLines: 2, overflow: .ellipsis),
      subtitle: Text(subtitle, maxLines: 2, overflow: .ellipsis),
      trailing: Column(
        mainAxisAlignment: .center,
        crossAxisAlignment: .end,
        children: <Widget>[
          ChatTaskStatusBadge(status: task.status),
          const SizedBox(height: AleraTokens.spaceXs),
          Text(
            agentChatTaskAgeLabel(task.updatedAt, now),
            style: theme.textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// One task inside a chat notice or dock, with the explicit ways to look
/// closer.
class const ChatTaskNoticeRow({
  super.key,
  required final AgentChatTask task,
  final VoidCallback? onView,
  final VoidCallback? onOpenChat,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AleraTokens.spaceXs),
    child: Row(
      children: <Widget>[
        ChatTaskStatusBadge(status: task.status),
        const SizedBox(width: AleraTokens.spaceSm),
        Expanded(
          child: Text(
            task.displayTitle,
            maxLines: 1,
            overflow: .ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
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

/// Who sent a message into this chat when it was another chat.
class const ChatMessageSenderRow({
  super.key,
  required final String senderTitle,
  final String? senderPlace,
  final VoidCallback? onOpenChat,
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
          <String>['From $senderTitle', ?senderPlace].join(' · '),
          maxLines: 1,
          overflow: .ellipsis,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: AleraTokens.foregroundMuted),
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

/// The tasks a chat delegated that still run or need someone.
class const ChatTaskDockView({
  super.key,
  required final List<AgentChatTask> tasks,
  required final ValueChanged<AgentChatTask> onView,
  final int total = 0,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();
    final muted = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    final more = total - tasks.length;
    return Container(
      key: const ValueKey<String>('chatTaskDock'),
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.spaceMd,
        vertical: AleraTokens.spaceXs,
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
          Text('Delegated Tasks', style: muted),
          for (final task in tasks)
            ChatTaskNoticeRow(task: task, onView: () => onView(task)),
          if (more > 0) Text('$more more in Activity', style: muted),
        ],
      ),
    );
  }
}
