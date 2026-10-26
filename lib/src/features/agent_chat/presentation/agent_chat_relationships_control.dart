import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/alera_popover.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_relationships.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_relationships_panel.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The chat's lineage behind one button: parent, fork source, forks,
/// delegated chats and native sub-agents. Hidden while the chat has none.
class const AgentChatRelationshipsControl({
  super.key,
  required final String chatId,
  required final String workspaceId,
  required final AgentChatRelationshipActions Function(
    AgentChatRelationships relationships,
    VoidCallback close,
  )
  actions,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentChatRelationshipsControl> createState() =>
      _AgentChatRelationshipsControlState();
}

class _AgentChatRelationshipsControlState
    extends ConsumerState<AgentChatRelationshipsControl> {
  final AleraPopoverController _popover = AleraPopoverController();

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final calls = ref.watch(
      agentChatControllerProvider(widget.chatId, widget.workspaceId).select(
        (state) => agentChatSubagentCalls(
          state.thread?.items ?? const <AgentChatItem>[],
        ),
      ),
    );
    final chats =
        ref.watch(agentChatRelatedChatsProvider).value ??
        const <AgentChatSummary>[];
    final relationships = AgentChatRelationships.build(
      chatId: widget.chatId,
      chats: chats,
      items: calls,
    );
    if (relationships.isEmpty) return const SizedBox.shrink();
    final running = relationships.runningCount;
    return AleraPopover(
      controller: _popover,
      toggleOnAnchorTap: false,
      width: AleraTokens.dialogCompactWidth,
      builder: (context, close) => AgentChatRelationshipsPanel(
        relationships: relationships,
        actions: widget.actions(relationships, close),
      ),
      child: Material(
        color: AleraTokens.surface,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: AleraTokens.borderSubtle),
          borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
        ),
        child: InkWell(
          key: const ValueKey<String>('agent-chat-lineage'),
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AleraTokens.radiusPill),
          ),
          onTap: _popover.toggle,
          child: Tooltip(
            message: relationships.heading,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AleraTokens.space8,
                vertical: AleraTokens.space4,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(AleraIcons.gitFork, size: AleraTokens.iconMd),
                  const SizedBox(width: AleraTokens.space4),
                  Text(
                    running == 0 ? 'Lineage' : 'Lineage · $running',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
