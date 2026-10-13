import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_workspace_activity.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_tab_activity.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The status dot of a chat tab, in the same colors terminal agents use:
/// working, waiting on the person, or failed. Idle chats show nothing.
class const AgentChatTabStatusDot({
  super.key,
  required final String workspaceId,
  required final String chatId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(
      agentChatWorkspaceActivityProvider(workspaceId)
          .select((chats) => chats[chatId] ?? AgentChatTabActivity.idle),
    );
    final (color, message) = switch (activity) {
      AgentChatTabActivity.working => (
        AleraTokens.info,
        'The agent is working',
      ),
      AgentChatTabActivity.needsInput => (
        AleraTokens.warning,
        'The agent is waiting for you',
      ),
      AgentChatTabActivity.failed => (AleraTokens.error, 'The agent stopped'),
      AgentChatTabActivity.idle => (null, null),
    };
    if (color == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: AleraTokens.space4),
      child: Tooltip(
        message: message,
        child: AleraStatusDot(
          key: ValueKey<String>('agent-chat-tab-status-$chatId'),
          active: true,
          size: AleraTokens.statusDotSm,
          color: color,
        ),
      ),
    );
  }
}
