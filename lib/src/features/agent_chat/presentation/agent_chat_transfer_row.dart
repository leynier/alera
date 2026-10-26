import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_relationships.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_activity_rows.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_find.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_preview_card.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_timeline_context.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_transfer_scope.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Context another chat moved into this one, as a divider row: "Forked
/// From", "Merged Back From", "Delegated By" or "Result From" the source
/// chat, with the transfer's status. The source opens on click and previews
/// on hover. A merge-back folds the work the fork handed back under it.
class const AgentChatTransferRowView({
  super.key,
  required final AgentChatTransferEntry entry,
  required final AgentChatExpansion expansion,
  required final AgentChatTimelineActions actions,
  required final String workspacePath,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentChatTransferRowView> createState() =>
      _AgentChatTransferRowViewState();
}

class _AgentChatTransferRowViewState
    extends ConsumerState<AgentChatTransferRowView> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transfer = widget.entry.transfer;
    final notice = widget.entry.notice;
    final chats =
        ref.watch(agentChatRelatedChatsProvider).value ??
        const <AgentChatSummary>[];
    final source = chats
        .where((chat) => chat.chatId == transfer.sourceChatId)
        .firstOrNull;
    final title = agentChatTransferSourceTitle(transfer, source);
    final openable = source != null && !source.archived;
    final onOpenChat = AgentChatTransferScope.maybeOf(context)?.onOpenChat;
    final onOpen = openable && onOpenChat != null
        ? () => onOpenChat(transfer.sourceChatId)
        : null;
    final key = widget.entry.key;
    final expanded =
        notice != null && widget.expansion.isExpanded(key, byDefault: false);
    final color = transfer.failed
        ? AleraTokens.error
        : AleraTokens.foregroundMuted;
    final style = theme.textTheme.labelSmall?.copyWith(color: color);
    final preview = AgentChatPreview.transfer(
      transfer,
      sourceTitle: title,
      source: source,
      providerLabel: agentChatProviderFallbackLabel,
    );
    return Padding(
      key: ValueKey<String>('agent-chat-transfer-${transfer.id}'),
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(child: _Rule()),
              const SizedBox(width: AleraTokens.space12),
              Flexible(
                flex: 4,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AleraTokens.space6,
                  runSpacing: AleraTokens.space4,
                  children: <Widget>[
                    Icon(
                      agentChatTransferIcon(transfer.kind),
                      size: AleraTokens.iconSm,
                      color: color,
                    ),
                    Text(transfer.kind.label, style: style),
                    AgentChatPreviewHover(
                      preview: preview,
                      child: _SourceLink(
                        transferId: transfer.id,
                        title: title,
                        onOpen: onOpen,
                      ),
                    ),
                    Text('· ${transfer.statusLabel}', style: style),
                    if (notice != null)
                      IconButton(
                        key: ValueKey<String>(
                          'agent-chat-transfer-toggle-${transfer.id}',
                        ),
                        tooltip: expanded
                            ? 'Hide Merged Work'
                            : 'Show Merged Work',
                        visualDensity: VisualDensity.compact,
                        iconSize: AleraTokens.iconSm,
                        onPressed: () => setState(
                          () => widget.expansion.set(key, expanded: !expanded),
                        ),
                        icon: Icon(
                          expanded
                              ? AleraIcons.chevronDown
                              : AleraIcons.chevronRight,
                          color: AleraTokens.foregroundFaint,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AleraTokens.space12),
              const Expanded(child: _Rule()),
            ],
          ),
          if (notice != null && expanded)
            AgentChatFindTarget(
              targetKey: agentChatFindItemTargetKey(notice.id),
              child: AgentChatItemRowView(
                item: notice,
                expansion: widget.expansion,
                actions: widget.actions,
                workspacePath: widget.workspacePath,
              ),
            ),
        ],
      ),
    );
  }
}

class const _SourceLink({
  required final String transferId,
  required final String title,
  required final VoidCallback? onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: onOpen == null ? AleraTokens.foregroundFaint : AleraTokens.accent,
    );
    return Semantics(
      link: onOpen != null,
      label: onOpen == null ? title : 'Open $title',
      child: InkWell(
        key: ValueKey<String>('agent-chat-transfer-source-$transferId'),
        borderRadius: BorderRadius.circular(AleraTokens.radiusSm),
        onTap: onOpen,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      ),
    );
  }
}

/// The icon of a transfer row and its lineage row.
IconData agentChatTransferIcon(AgentChatTransferKind kind) => switch (kind) {
  AgentChatTransferKind.fork => AleraIcons.gitFork,
  AgentChatTransferKind.mergeBack => AleraIcons.gitMerge,
  AgentChatTransferKind.subagentSpawn ||
  AgentChatTransferKind.subagentResult => AleraIcons.agent,
  AgentChatTransferKind.providerHandoff ||
  AgentChatTransferKind.unknown => AleraIcons.forward,
};

class const _Rule() extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const Divider(
    height: AleraTokens.dividerExtent,
    color: AleraTokens.borderSubtle,
  );
}
