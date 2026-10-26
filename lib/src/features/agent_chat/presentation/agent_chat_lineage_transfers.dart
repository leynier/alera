import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_preview_card.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_transfer_row.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';

const int _initialRows = 4;

/// The context moved into the chat, under the lineage rows, as T3 Code's
/// relationships control lists its transfer edges: one row per transfer
/// with the source chat, how the context came and its status. A row opens
/// its source and previews it on hover; the list folds past a few rows.
class const AgentChatLineageTransfers({
  super.key,
  required final List<AgentChatTransferRelation> transfers,
  required final ValueChanged<String> onOpenChat,
}) extends StatefulWidget {
  @override
  State<AgentChatLineageTransfers> createState() =>
      _AgentChatLineageTransfersState();
}

class _AgentChatLineageTransfersState extends State<AgentChatLineageTransfers> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final transfers = widget.transfers;
    if (transfers.isEmpty) return const SizedBox.shrink();
    final visible = _all ? transfers : transfers.take(_initialRows).toList();
    final hidden = transfers.length - visible.length;
    return Column(
      key: const ValueKey<String>('agent-chat-lineage-transfers'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AleraTokens.space6,
            AleraTokens.space8,
            AleraTokens.space6,
            AleraTokens.space4,
          ),
          child: Text(
            'Context Transfers',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: AleraTokens.foregroundFaint),
          ),
        ),
        for (final relation in visible)
          _TransferRow(
            key: ValueKey<String>('agent-chat-lineage-${relation.key}'),
            relation: relation,
            onOpenChat: widget.onOpenChat,
          ),
        if (hidden > 0)
          TextButton.icon(
            key: const ValueKey<String>('agent-chat-lineage-more-transfers'),
            onPressed: () => setState(() => _all = true),
            icon: const Icon(AleraIcons.add, size: AleraTokens.iconMd),
            label: Text('Show $hidden More'),
          ),
      ],
    );
  }
}

class const _TransferRow({
  super.key,
  required final AgentChatTransferRelation relation,
  required final ValueChanged<String> onOpenChat,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transfer = relation.transfer;
    final color = transfer.failed
        ? AleraTokens.error
        : AleraTokens.foregroundMuted;
    return AgentChatPreviewHover(
      preview: AgentChatPreview.transfer(
        transfer,
        sourceTitle: relation.title,
        source: relation.source,
        providerLabel: agentChatProviderFallbackLabel,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        onTap: relation.missing ? null : () => onOpenChat(relation.chatId),
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space6),
          child: Row(
            children: <Widget>[
              Icon(
                agentChatTransferIcon(transfer.kind),
                size: AleraTokens.iconMd,
                color: color,
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  relation.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: relation.missing
                        ? AleraTokens.foregroundFaint
                        : AleraTokens.foreground,
                  ),
                ),
              ),
              const SizedBox(width: AleraTokens.space6),
              Flexible(
                child: Text(
                  '${transfer.kind.label} · ${transfer.statusLabel}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: transfer.failed
                        ? AleraTokens.error
                        : AleraTokens.foregroundFaint,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
