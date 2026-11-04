import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_tab_actions.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_history_actions.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_provider_identity.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

/// Closed chats of a workspace, newest first. Their history stays on the
/// host; Reopen continues one in a new tab and returns that tab's id, which
/// the caller selects because the person asked for it.
Future<String?> showAgentChatArchivedChatsSheet(
  BuildContext context, {
  required String hostId,
  required String workspaceId,
}) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: _ArchivedChatsPanel(hostId: hostId, workspaceId: workspaceId),
    ),
  ),
);

class const _ArchivedChatsPanel({
  required final String hostId,
  required final String workspaceId,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ArchivedChatsPanel> createState() =>
      _ArchivedChatsPanelState();
}

class _ArchivedChatsPanelState extends ConsumerState<_ArchivedChatsPanel> {
  static final Logger _logger = Logger('AgentChatArchivedChats');
  String? _reopening;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final archived = ref.watch(
      agentChatArchivedChatsProvider(widget.hostId, widget.workspaceId),
    );
    return switch (archived) {
      AsyncValue(value: final chats?) => _list(chats),
      AsyncError(:final error) => AleraEmptyState(
        icon: AleraIcons.loadFailed,
        title: 'Could not load archived chats',
        message: agentChatErrorMessage(error),
        action: TextButton(
          onPressed: () => ref.invalidate(
            agentChatArchivedChatsProvider(widget.hostId, widget.workspaceId),
          ),
          child: const Text(agentChatTryAgainLabel),
        ),
      ),
      _ => const Padding(
        padding: AleraTokens.pagePadding,
        child: Center(child: CircularProgressIndicator()),
      ),
    };
  }

  Widget _list(List<AgentChatSummary> chats) {
    final canDelete =
        ref
            .watch(
              agentChatCapabilityProvider(
                widget.hostId,
                AgentChatWire.deleteCapability,
              ),
            )
            .value ??
        false;
    if (chats.isEmpty) {
      return const AleraEmptyState(
        icon: AleraIcons.archive,
        title: 'No archived chats',
        message: 'Chats you close in this workspace are kept here.',
      );
    }
    return ListView(
      shrinkWrap: true,
      children: <Widget>[
        const AleraSectionHeader(label: agentChatArchivedChatsLabel),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space16,
            ),
            child: Text(
              error,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AleraTokens.error),
            ),
          ),
        for (final chat in chats)
          ListTile(
            minTileHeight: AleraTokens.minTapTarget,
            leading: AgentIdentityIcon(
              agentType: agentChatAgentType(chat.provider),
              size: AleraTokens.space20,
              showTooltip: false,
            ),
            title: Text(
              chat.title.isEmpty ? 'Untitled chat' : chat.title,
              overflow: .ellipsis,
            ),
            subtitle: Text(
              MaterialLocalizations.of(context)
                  .formatMediumDate(chat.updatedAt.toLocal()),
            ),
            trailing: _reopening == chat.chatId
                ? const SizedBox.square(
                    dimension: AleraTokens.space16,
                    child: CircularProgressIndicator(
                      strokeWidth: AleraTokens.strokeSm,
                    ),
                  )
                : Wrap(
                    crossAxisAlignment: .center,
                    children: <Widget>[
                      TextButton(
                        onPressed: _reopening == null
                            ? () => _reopen(chat)
                            : null,
                        child: const Text('Reopen'),
                      ),
                      if (canDelete)
                        IconButton(
                          tooltip: 'Delete Chat',
                          onPressed: _reopening == null
                              ? () => _delete(chat)
                              : null,
                          icon: const Icon(AleraIcons.delete),
                        ),
                    ],
                  ),
          ),
      ],
    );
  }

  Future<void> _delete(AgentChatSummary chat) async {
    if (!await confirmAgentChatDelete(context) || !mounted) return;
    setState(() {
      _reopening = chat.chatId;
      _error = null;
    });
    try {
      final actions = await ref.read(
        agentChatTabActionsProvider(widget.hostId).future,
      );
      await actions.delete(workspaceId: chat.workspaceId, chatId: chat.chatId);
      ref.invalidate(
        agentChatArchivedChatsProvider(widget.hostId, widget.workspaceId),
      );
    } on Object catch (error, stackTrace) {
      _logger.warning('Could not delete a chat.', error, stackTrace);
      if (mounted) setState(() => _error = agentChatErrorMessage(error));
    } finally {
      if (mounted) setState(() => _reopening = null);
    }
  }

  Future<void> _reopen(AgentChatSummary chat) async {
    setState(() {
      _reopening = chat.chatId;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      final actions = await ref.read(
        agentChatTabActionsProvider(widget.hostId).future,
      );
      final result = await actions.reopen(
        workspaceId: chat.workspaceId,
        chatId: chat.chatId,
      );
      if (navigator.mounted) navigator.pop(result.tabId);
    } on Object catch (error, stackTrace) {
      _logger.warning('Could not reopen a chat.', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _reopening = null;
        _error = agentChatErrorMessage(error);
      });
    }
  }
}
