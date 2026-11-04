import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_open_actions.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The sender line of a queued message the person did not write, or null.
Widget? agentChatQueueSenderOf(AgentChatQueueEntry entry) =>
    switch (agentChatMessageSender(entry.origin)) {
      final sender? => AgentChatQueueSender(
        key: ValueKey<String>('queue-sender-${entry.queueId}'),
        sender: sender,
      ),
      null => null,
    };

/// "Automation · Nightly report", "Pull request #42", "Guest · Ana", or
/// "Agent · Planner" with Open Chat when the sending chat's workspace is open
/// here.
class const AgentChatQueueSender({
  super.key,
  required final AgentChatMessageSender sender,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatId = sender.chatId;
    final chat = chatId == null
        ? null
        : ref.watch(chatTaskChatProvider(chatId)).value;
    final title = chat?.title.trim() ?? '';
    final style = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: AleraTokens.foregroundMuted);
    return Padding(
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
              style: style,
            ),
          ),
          if (chat != null && chatTaskWorkspaceKnown(ref, chat.workspaceId))
            TextButton(
              key: const ValueKey<String>('queue-sender-open-chat'),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: style,
              ),
              onPressed: () => unawaited(
                openChatTaskChat(
                  context,
                  ref,
                  chatId: chat.chatId,
                  workspaceId: chat.workspaceId,
                ),
              ),
              child: const Text('Open Chat'),
            ),
        ],
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
