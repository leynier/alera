import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/features/chat_tasks/application/chat_workspace_attention.dart';
import 'package:alera/src/features/chat_tasks/domain/chat_attention_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dot color for what a workspace's chats want, in the tab dot colors.
Color? chatAttentionColor(ChatAttentionLevel level) => switch (level) {
  ChatAttentionLevel.needsInput => AleraTokens.warning,
  ChatAttentionLevel.failed => AleraTokens.error,
  ChatAttentionLevel.unread => AleraTokens.success,
  ChatAttentionLevel.working => AleraTokens.info,
  ChatAttentionLevel.waitingOnTasks => AleraTokens.foregroundMuted,
  ChatAttentionLevel.idle => null,
};

/// The agent chats of a workspace, beside its sidebar name: one dot for the
/// most urgent, with every count in the tooltip. Shows nothing while they
/// are idle and never navigates.
class const ChatWorkspaceAttentionDot({
  super.key,
  required final String workspaceId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attention = ref.watch(
      chatWorkspaceAttentionProvider.select((all) => all[workspaceId]),
    );
    final color = attention == null
        ? null
        : chatAttentionColor(attention.level);
    if (attention == null || color == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: AleraTokens.space6),
      child: Tooltip(
        message: attention.description,
        child: Semantics(
          label: 'Agent chats: ${attention.description}',
          child: AleraStatusDot(
            key: ValueKey<String>('workspace-chat-attention-$workspaceId'),
            active: true,
            size: AleraTokens.statusDotSm,
            color: color,
          ),
        ),
      ),
    );
  }
}
