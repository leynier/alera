import 'dart:async';

import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_relationships.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_item_rows.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_markdown.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_preview_sheet.dart';
import 'package:alera_mobile/src/features/chat_tasks/presentation/chat_task_open.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Context another chat moved into this one, as the desktop draws it: "Forked
/// From", "Merged Back From", "Delegated By" or "Result From" the source chat
/// with the transfer's status. A tap opens the source, a long press previews
/// it, and a merge-back folds the work the fork handed back under it.
class const AgentChatTransferRowView({
  super.key,
  required final AgentChatTransferEntry entry,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentChatTransferRowView> createState() =>
      _AgentChatTransferRowViewState();
}

class _AgentChatTransferRowViewState
    extends ConsumerState<AgentChatTransferRowView> {
  late bool _expanded = agentChatFoldExpanded(
    context,
    widget.entry.key,
    fallback: false,
  );

  void _toggle() {
    setState(() => _expanded = !_expanded);
    agentChatRememberFold(context, widget.entry.key, expanded: _expanded);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transfer = widget.entry.transfer;
    final notice = widget.entry.notice;
    final scope = AgentChatScope.maybeOf(context);
    final chats = scope == null
        ? const <AgentChatSummary>[]
        : ref.watch(agentChatRelatedChatsProvider(scope.hostId)).value ??
              const <AgentChatSummary>[];
    final source = chats
        .where((chat) => chat.chatId == transfer.sourceChatId)
        .firstOrNull;
    final title = agentChatTransferSourceTitle(transfer, source);
    final color = transfer.failed
        ? AleraTokens.error
        : AleraTokens.foregroundMuted;
    final open = scope != null && source != null && !source.archived
        ? () => unawaited(
            openMobileChatTaskChat(
              context,
              ref,
              hostId: scope.hostId,
              chatId: source.chatId,
              workspaceId: source.workspaceId,
            ),
          )
        : null;
    return Column(
      key: ValueKey<String>('agent-chat-transfer-${transfer.id}'),
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Semantics(
          button: open != null,
          label: '${transfer.kind.label} $title, ${transfer.statusLabel}',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(AleraTokens.radiusMd),
            onTap: open,
            onLongPress: () => showAgentChatPreviewSheet(
              context,
              AgentChatPreview.transfer(
                transfer,
                sourceTitle: title,
                source: source,
                providerLabel: agentChatPreviewProviderLabel,
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AleraTokens.minTapTarget,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    switch (transfer.kind) {
                      AgentChatTransferKind.fork => AleraIcons.gitFork,
                      AgentChatTransferKind.mergeBack => AleraIcons.gitMerge,
                      _ => AleraIcons.agent,
                    },
                    size: AleraTokens.space16,
                    color: color,
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  Expanded(
                    child: Text(
                      '${transfer.kind.label} $title',
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: color),
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space6),
                  Text(
                    transfer.statusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: transfer.failed
                          ? AleraTokens.error
                          : AleraTokens.foregroundFaint,
                    ),
                  ),
                  if (notice != null)
                    IconButton(
                      key: ValueKey<String>(
                        'agent-chat-transfer-toggle-${transfer.id}',
                      ),
                      tooltip: _expanded
                          ? 'Hide Merged Work'
                          : 'Show Merged Work',
                      onPressed: _toggle,
                      icon: Icon(
                        _expanded
                            ? AleraIcons.chevronDown
                            : AleraIcons.chevronRight,
                        size: AleraTokens.space16,
                        color: AleraTokens.foregroundFaint,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (notice != null && _expanded) AgentChatItemRowView(item: notice),
      ],
    );
  }
}
