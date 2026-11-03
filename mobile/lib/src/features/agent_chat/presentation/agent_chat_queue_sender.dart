import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/chat_tasks/application/mobile_chat_task_providers.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_open.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The sender line of a queued message the person did not write, or null.
Widget? agentChatQueueSenderOf(String hostId, AgentChatQueueEntry entry) =>
    switch (agentChatMessageSender(entry.origin)) {
      final sender? => AgentChatQueueSender(
        key: ValueKey<String>('queue-sender-${entry.queueId}'),
        hostId: hostId,
        sender: sender,
      ),
      null => null,
    };

/// "Automation · Nightly report", "Pull request #42", "Guest · Ana", or
/// "Agent · Planner", which opens the sending chat when tapped.
class const AgentChatQueueSender({
  super.key,
  required final String hostId,
  required final AgentChatMessageSender sender,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatId = sender.chatId;
    final chat = chatId == null
        ? null
        : ref.watch(mobileChatTaskChatProvider(hostId, chatId)).value;
    final title = chat?.title.trim() ?? '';
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    final line = Padding(
      padding: const EdgeInsets.only(top: AleraTokens.space4),
      child: Row(
        children: <Widget>[
          Icon(
            agentChatSenderIcon(sender.kind),
            size: AleraTokens.space12,
            color: AleraTokens.foregroundMuted,
          ),
          const SizedBox(width: AleraTokens.space4),
          Flexible(
            child: Text(
              title.isEmpty ? sender.text : '${sender.label} · $title',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: chat == null
                  ? style
                  : style?.copyWith(decoration: TextDecoration.underline),
            ),
          ),
        ],
      ),
    );
    if (chat == null) return line;
    return Semantics(
      button: true,
      label: 'Open ${chat.title}',
      child: InkWell(
        key: const ValueKey<String>('queue-sender-open-chat'),
        onTap: () => unawaited(
          openMobileChatTaskChat(
            context,
            ref,
            hostId: hostId,
            chatId: chat.chatId,
            workspaceId: chat.workspaceId,
          ),
        ),
        child: line,
      ),
    );
  }
}

IconData agentChatSenderIcon(AgentChatMessageSenderKind kind) => switch (kind) {
  .automation => AleraIcons.schedule,
  .pullRequestWatch => AleraIcons.gitPullRequest,
  .agent => AleraIcons.agent,
  .guest => AleraIcons.account,
};
