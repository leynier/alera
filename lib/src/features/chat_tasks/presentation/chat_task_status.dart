import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/widgets.dart';

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

/// `Codex · gpt-5`: the child chat's agent as rows and the detail name it.
String chatTaskAgentLabel(AgentChatTask task) {
  final provider = task.provider;
  final name = provider == null
      ? null
      : agentChatProviderFallbackLabel(provider);
  return <String>[?name, ?task.model].join(' · ');
}

/// The row subtitle: status, why it needs attention, and its agent.
String chatTaskRowSubtitle(AgentChatTask task) => <String>[
  agentChatTaskStatusLabel(task.status),
  ?agentChatTaskAttentionLabel(task),
  if (chatTaskAgentLabel(task) case final agent when agent.isNotEmpty) agent,
].join(' · ');
