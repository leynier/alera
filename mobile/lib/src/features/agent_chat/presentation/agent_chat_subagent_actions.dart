import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_subagent_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// The chat a sub-agent belongs to, as the phone addresses it.
final class const AgentChatSubagentChat({
  required final String hostId,
  required final String workspaceId,
  required final String chatId,
}) {
  AgentChatRef get ref =>
      AgentChatRef(chatId: chatId, workspaceId: workspaceId);
}

/// Pushes the sub-agent the call [callId] started as its own screen. Only a
/// press opens it; nothing here navigates on its own.
Future<void> openAgentChatSubagent(
  BuildContext context,
  AgentChatSubagentChat chat,
  String callId,
) => Navigator.of(context).push<void>(
  MaterialPageRoute<void>(
    builder: (_) => AgentChatSubagentScreen(chat: chat, callId: callId),
  ),
);

/// Stops the running sub-agent [callId] started, reporting a refusal.
Future<void> stopAgentChatSubagent(
  BuildContext context,
  WidgetRef ref,
  AgentChatSubagentChat chat,
  String callId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final repository = await ref.read(
      agentChatRepositoryProvider(chat.hostId).future,
    );
    await repository.lifecycle.stopSubagent(
      chat.ref,
      requestId: _uuid.v4(),
      itemId: callId,
    );
  } on Object catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Could not stop the sub-agent: ${agentChatErrorMessage(error)}',
        ),
      ),
    );
  }
}

/// Hands the fork [chat] to the chat it was forked from, for that chat's
/// next turn, and says so.
Future<void> mergeBackAgentChat(
  BuildContext context,
  WidgetRef ref,
  AgentChatSubagentChat chat,
  String targetTitle,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final repository = await ref.read(
      agentChatRepositoryProvider(chat.hostId).future,
    );
    await repository.lifecycle.mergeBack(chat.ref, requestId: _uuid.v4());
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Merged into $targetTitle. Its agent reads the work with the next '
          'message.',
        ),
      ),
    );
  } on Object catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text('Could not merge back: ${agentChatErrorMessage(error)}'),
      ),
    );
  }
}

/// Open and, while it runs, Stop for a sub-agent row, each only when the
/// runtime (`agentChatSubagentThreadsV1`) and the chat's provider allow it.
class const AgentChatSubagentRowActions({
  super.key,
  required final AgentChatItem call,
  required final bool running,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = AgentChatScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    final chat = AgentChatSubagentChat(
      hostId: scope.hostId,
      workspaceId: scope.workspaceId,
      chatId: scope.chatId,
    );
    final threads =
        ref
            .watch(
              agentChatCapabilityProvider(
                chat.hostId,
                AgentChatWire.subagentThreadsCapability,
              ),
            )
            .value ??
        false;
    if (!threads) return const SizedBox.shrink();
    final stoppable =
        running &&
        ref.watch(
          agentChatControllerProvider(
            chat.hostId,
            chat.workspaceId,
            chat.chatId,
          ).select(
            (state) =>
                state.value?.thread.session.capabilities.stopSubagent ?? false,
          ),
        );
    return Row(
      mainAxisSize: .min,
      children: <Widget>[
        if (stoppable)
          IconButton(
            key: ValueKey<String>('agent-chat-subagent-stop-${call.id}'),
            tooltip: 'Stop Sub-agent',
            icon: const Icon(
              AleraIcons.stopSubagent,
              size: AleraTokens.space16,
              color: AleraTokens.error,
            ),
            onPressed: () =>
                unawaited(stopAgentChatSubagent(context, ref, chat, call.id)),
          ),
        IconButton(
          key: ValueKey<String>('agent-chat-subagent-open-${call.id}'),
          tooltip: 'Open Sub-agent',
          icon: const Icon(AleraIcons.chevronRight, size: AleraTokens.space16),
          onPressed: () =>
              unawaited(openAgentChatSubagent(context, chat, call.id)),
        ),
      ],
    );
  }
}
