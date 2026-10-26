import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_preview_sheet.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_subagent_actions.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_open.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The context moved into the chat, under the lineage rows of the sheet: one
/// tile per transfer that opens its source chat, previewed on long press.
class const AgentChatLineageTransferTiles({
  super.key,
  required final AgentChatSubagentChat chat,
  required final List<AgentChatTransferRelation> transfers,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (transfers.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey<String>('agent-chat-lineage-transfers'),
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AleraTokens.space16,
            AleraTokens.space12,
            AleraTokens.space16,
            AleraTokens.space4,
          ),
          child: Text(
            'Context Transfers',
            style: theme.textTheme.labelMedium?.copyWith(
              color: AleraTokens.foregroundFaint,
            ),
          ),
        ),
        for (final relation in transfers)
          ListTile(
            key: ValueKey<String>('agent-chat-lineage-${relation.key}'),
            leading: Icon(switch (relation.transfer.kind) {
              AgentChatTransferKind.fork => AleraIcons.gitFork,
              AgentChatTransferKind.mergeBack => AleraIcons.gitMerge,
              _ => AleraIcons.agent,
            }, color: relation.transfer.failed ? AleraTokens.error : null),
            title: Text(relation.title, maxLines: 1, overflow: .ellipsis),
            subtitle: Text(
              '${relation.transfer.kind.label} · '
              '${relation.transfer.statusLabel}',
            ),
            onTap: switch (relation.source) {
              final source? when !relation.missing => () => unawaited(
                openMobileChatTaskChat(
                  context,
                  ref,
                  hostId: chat.hostId,
                  chatId: source.chatId,
                  workspaceId: source.workspaceId,
                ),
              ),
              _ => null,
            },
            onLongPress: () => showAgentChatPreviewSheet(
              context,
              AgentChatPreview.transfer(
                relation.transfer,
                sourceTitle: relation.title,
                source: relation.source,
                providerLabel: agentChatPreviewProviderLabel,
              ),
            ),
          ),
      ],
    );
  }
}
