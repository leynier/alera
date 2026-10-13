import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera_mobile/src/features/agent_chat/presentation/agent_chat_provider_identity.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

/// Picks an agent and model and starts a chat on the paired runtime.
/// Returns the new chat's tab id, which the caller selects: the person asked
/// for this chat, so opening it is not an unrequested navigation.
Future<String?> showNewAgentChatSheet(
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
      child: _NewAgentChatPanel(hostId: hostId, workspaceId: workspaceId),
    ),
  ),
);

class const _NewAgentChatPanel({
  required final String hostId,
  required final String workspaceId,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<_NewAgentChatPanel> createState() => _NewAgentChatPanelState();
}

class _NewAgentChatPanelState extends ConsumerState<_NewAgentChatPanel> {
  /// One id for this sheet, so pressing Start again after a timeout returns
  /// the chat the first press created instead of a second one.
  final String _requestId = const Uuid().v4();
  String? _providerId;
  String? _modelId;
  bool _creating = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final providers = ref.watch(
      agentChatProvidersProvider(widget.hostId, widget.workspaceId),
    );
    return switch (providers) {
      AsyncValue(value: final list?) => _content(list),
      AsyncError(:final error) => AleraEmptyState(
        icon: AleraIcons.loadFailed,
        title: 'Could not load agents',
        message: agentChatErrorMessage(error),
        action: TextButton(
          onPressed: () => ref.invalidate(
            agentChatProvidersProvider(widget.hostId, widget.workspaceId),
          ),
          child: const Text('Retry'),
        ),
      ),
      _ => const Padding(
        padding: AleraTokens.pagePadding,
        child: Center(child: CircularProgressIndicator()),
      ),
    };
  }

  Widget _content(List<AgentChatProviderInstance> providers) {
    if (providers.isEmpty) {
      return const AleraEmptyState(
        icon: AleraIcons.agent,
        title: 'No agents available',
        message: 'Install or configure an agent on the host to start a chat.',
      );
    }
    AgentChatProviderInstance? selected;
    for (final provider in providers) {
      if (provider.id == _providerId) selected = provider;
    }
    final models = selected?.models ?? const <AgentChatModelOption>[];
    final modelId = _modelId ?? selected?.initialModel?.id;
    return ListView(
      shrinkWrap: true,
      children: <Widget>[
        const AleraSectionHeader(label: 'Agent'),
        for (final provider in providers)
          ListTile(
            minTileHeight: AleraTokens.minTapTarget,
            leading: AgentIdentityIcon(
              agentType: agentChatAgentType(provider.provider),
              size: AleraTokens.space20,
              showTooltip: false,
            ),
            title: Text(provider.label),
            subtitle: provider.available
                ? null
                : Text(provider.unavailableReason ?? 'Not available'),
            enabled: provider.available && !_creating,
            selected: provider.id == _providerId,
            trailing: provider.id == _providerId
                ? const Icon(AleraIcons.check)
                : null,
            onTap: () => setState(() {
              _providerId = provider.id;
              _modelId = null;
            }),
          ),
        if (models.length > 1) ...<Widget>[
          const AleraSectionHeader(label: 'Model'),
          for (final model in models)
            ListTile(
              minTileHeight: AleraTokens.minTapTarget,
              title: Text(model.label),
              enabled: !_creating,
              trailing: model.id == modelId
                  ? const Icon(AleraIcons.check)
                  : null,
              onTap: () => setState(() => _modelId = model.id),
            ),
        ],
        if (_error case final String error)
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
        Padding(
          padding: AleraTokens.pagePadding,
          child: FilledButton(
            onPressed: selected == null || _creating
                ? null
                : () => _create(selected!, modelId),
            child: _creating
                ? const SizedBox.square(
                    dimension: AleraTokens.space16,
                    child: CircularProgressIndicator(
                      strokeWidth: AleraTokens.strokeSm,
                    ),
                  )
                : const Text('Start Chat'),
          ),
        ),
        ..._archived(),
      ],
    );
  }

  /// Closed chats keep their history on the host; Reopen continues one in a
  /// new tab instead of starting over.
  List<Widget> _archived() {
    final chats =
        ref
            .watch(
              agentChatArchivedChatsProvider(widget.hostId, widget.workspaceId),
            )
            .value ??
        const <AgentChatSummary>[];
    if (chats.isEmpty) return const <Widget>[];
    return <Widget>[
      const AleraSectionHeader(label: 'Archived Chats'),
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
          trailing: TextButton(
            onPressed: _creating ? null : () => _reopen(chat),
            child: const Text('Reopen'),
          ),
        ),
    ];
  }

  Future<void> _reopen(AgentChatSummary chat) async {
    setState(() {
      _creating = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      final repository = await ref.read(
        agentChatRepositoryProvider(widget.hostId).future,
      );
      final result = await repository.reopen(
        AgentChatRef(chatId: chat.chatId, workspaceId: chat.workspaceId),
        requestId: const Uuid().v4(),
      );
      if (navigator.mounted) navigator.pop(result.tabId);
    } on Object catch (error, stackTrace) {
      Logger('NewAgentChatSheet')
          .warning('Could not reopen a chat.', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = agentChatErrorMessage(error);
      });
    }
  }

  Future<void> _create(
    AgentChatProviderInstance provider,
    String? modelId,
  ) async {
    setState(() {
      _creating = true;
      _error = null;
    });
    final navigator = Navigator.of(context);
    try {
      final repository = await ref.read(
        agentChatRepositoryProvider(widget.hostId).future,
      );
      final result = await repository.create(
        AgentChatCreateInput(
          requestId: _requestId,
          workspaceId: widget.workspaceId,
          provider: provider.provider,
          providerInstanceId: provider.id,
          model: modelId,
        ),
      );
      if (navigator.mounted) navigator.pop(result.tabId);
    } on Object catch (error, stackTrace) {
      Logger('NewAgentChatSheet')
          .warning('Could not start a chat.', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _creating = false;
        _error = agentChatErrorMessage(error);
      });
    }
  }
}
