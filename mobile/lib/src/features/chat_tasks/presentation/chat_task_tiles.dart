import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/badges/alera_badge.dart';
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
