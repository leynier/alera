import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_checkbox.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_archived_list.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_composer_controls.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_provider_icon.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Asks which agent should answer, creates the chat on the runtime and opens
/// its tab in [targetGroupId]. The tab only takes focus while the person is
/// still on [workspace].
Future<void> showNewAgentChatFlow(
  BuildContext context,
  WidgetRef ref, {
  required Workspace workspace,
  String? targetGroupId,
}) async {
  final result = await showDialog<AgentChatOpenResult>(
    context: context,
    builder: (_) => NewAgentChatDialog(workspace: workspace),
  );
  final tabId = result?.tabId;
  if (tabId == null) return;
  await ref
      .read(workbenchControllerProvider.notifier)
      .openPersistedWorkspaceTab(
        workspaceId: workspace.id,
        tabId: tabId,
        targetGroupId: targetGroupId,
        activateOnlyIfCurrent: true,
      );
}

class const NewAgentChatDialog({super.key, required final Workspace workspace})
    extends ConsumerStatefulWidget {
  @override
  ConsumerState<NewAgentChatDialog> createState() => _NewAgentChatDialogState();
}

class _NewAgentChatDialogState extends ConsumerState<NewAgentChatDialog> {
  // One id per dialog: a retried create returns the same chat.
  late final String _requestId = ref.read(agentChatIdGeneratorProvider)();
  String? _providerInstanceId;
  String? _model;
  AgentChatRuntimeMode? _runtimeMode;
  bool _plan = false;
  bool _creating = false;
  String? _error;
  late final AgentChatReopenIds _reopenIds = AgentChatReopenIds(
    ref.read(agentChatIdGeneratorProvider),
  );
  late final Future<List<AgentChatSummary>> _archived = loadArchivedAgentChats(
    ref.read(agentChatRepositoryProvider),
    widget.workspace.id,
  );
  String? _reopeningChatId;

  bool get _opening => _creating || _reopeningChatId != null;

  void _dismiss() {
    if (!_opening) Navigator.of(context).pop();
  }

  Future<void> _reopen(AgentChatSummary chat) async {
    if (_opening) return;
    setState(() {
      _reopeningChatId = chat.chatId;
      _error = null;
    });
    try {
      final result = await ref
          .read(agentChatRepositoryProvider)
          .reopen(
            AgentChatRef(chatId: chat.chatId, workspaceId: chat.workspaceId),
            requestId: _reopenIds.forChat(chat.chatId),
          );
      if (mounted) Navigator.of(context).pop(result);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _reopeningChatId = null;
          _error = agentChatErrorMessage(error);
        });
      }
    }
  }

  AgentChatProviderInstance? _selected(List<AgentChatProviderInstance> all) {
    final available = all.where((instance) => instance.available).toList();
    final preferred =
        _providerInstanceId ?? ref.read(agentChatLaunchPreferenceProvider);
    return available
            .where((instance) => instance.id == preferred)
            .firstOrNull ??
        available.firstOrNull;
  }

  Future<void> _create(AgentChatProviderInstance instance) async {
    if (_opening) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final modes = instance.runtimeModes;
      final result = await ref
          .read(agentChatRepositoryProvider)
          .create(
            AgentChatCreateInput(
              requestId: _requestId,
              workspaceId: widget.workspace.id,
              provider: instance.provider,
              providerInstanceId: instance.id,
              model: _model ?? instance.initialModel?.id,
              runtimeMode:
                  _runtimeMode ??
                  (modes.contains(AgentChatRuntimeMode.approvalRequired)
                      ? AgentChatRuntimeMode.approvalRequired
                      : modes.firstOrNull),
              interactionMode: _plan ? AgentChatInteractionMode.plan : null,
            ),
          );
      if (!mounted) return;
      ref
          .read(agentChatLaunchPreferenceProvider.notifier)
          .remember(instance.id);
      Navigator.of(context).pop(result);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _creating = false;
          _error = agentChatErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final catalog = ref.watch(
      agentChatProviderCatalogProvider(widget.workspace.id),
    );
    return PopScope(
      canPop: !_opening,
      child: AleraDialog(
        maxWidth: AleraTokens.dialogCompactWidth,
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AleraDialogHeader(title: 'New Agent Chat', onClose: _dismiss),
              const SizedBox(height: AleraTokens.space8),
              Text(
                'The chat runs on the Alera runtime of ${widget.workspace.name} '
                'and keeps going when this window closes.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AleraTokens.foregroundMuted,
                ),
              ),
              const SizedBox(height: AleraTokens.space16),
              ...switch (catalog) {
                AsyncData(:final value) => _form(context, value),
                AsyncError(:final error) => <Widget>[
                  AleraInlineNotice(
                    tone: AleraInlineNoticeTone.error,
                    message: agentChatErrorMessage(error),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => ref.invalidate(
                          agentChatProviderCatalogProvider(widget.workspace.id),
                        ),
                        child: const Text('Try Again'),
                      ),
                    ),
                  ),
                ],
                _ => const <Widget>[
                  AleraEmptyState(message: 'Loading agents', loading: true),
                ],
              },
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _form(
    BuildContext context,
    List<AgentChatProviderInstance> providers,
  ) {
    final selected = _selected(providers);
    if (selected == null) {
      return <Widget>[
        AleraInlineNotice(
          tone: AleraInlineNoticeTone.warning,
          message: providers.isEmpty
              ? 'This runtime has no agent providers configured.'
              : 'No agent provider is available on this runtime. '
                        '${providers.first.unavailableReason ?? ''}'
                    .trim(),
        ),
      ];
    }
    final models = selected.models;
    final modes = selected.runtimeModes;
    return <Widget>[
      AleraDropdownField<String>(
        key: const ValueKey<String>('new-agent-chat-provider'),
        labelText: 'Agent',
        value: selected.id,
        enabled: !_opening,
        entries: <AleraDropdownFieldEntry<String>>[
          for (final instance in providers)
            AleraDropdownFieldEntry<String>(
              value: instance.id,
              label: instance.label,
              enabled: instance.available,
              detail: instance.available ? null : instance.unavailableReason,
              leading: AgentChatProviderIcon(
                provider: instance.provider,
                size: AleraTokens.iconMd,
              ),
            ),
        ],
        onChanged: (id) => setState(() {
          _providerInstanceId = id;
          _model = null;
          _runtimeMode = null;
          _plan = false;
        }),
      ),
      if (models.length > 1) ...<Widget>[
        const SizedBox(height: AleraTokens.space12),
        AleraDropdownField<String>(
          key: const ValueKey<String>('new-agent-chat-model'),
          labelText: 'Model',
          value: _model ?? selected.initialModel?.id,
          enabled: !_opening,
          filterable: models.length > 8,
          entries: <AleraDropdownFieldEntry<String>>[
            for (final model in models)
              AleraDropdownFieldEntry<String>(
                value: model.id,
                label: model.label,
                detail: model.isDefault ? 'Default' : null,
              ),
          ],
          onChanged: (id) => setState(() => _model = id),
        ),
      ],
      if (modes.length > 1) ...<Widget>[
        const SizedBox(height: AleraTokens.space12),
        AleraDropdownField<AgentChatRuntimeMode>(
          key: const ValueKey<String>('new-agent-chat-runtime-mode'),
          labelText: 'Approvals',
          value:
              _runtimeMode ??
              (modes.contains(AgentChatRuntimeMode.approvalRequired)
                  ? AgentChatRuntimeMode.approvalRequired
                  : modes.first),
          enabled: !_opening,
          entries: <AleraDropdownFieldEntry<AgentChatRuntimeMode>>[
            for (final mode in modes)
              AleraDropdownFieldEntry<AgentChatRuntimeMode>(
                value: mode,
                label: agentChatRuntimeModeLabel(mode),
              ),
          ],
          onChanged: (mode) => setState(() => _runtimeMode = mode),
        ),
      ],
      if (selected.supportsPlanMode) ...<Widget>[
        const SizedBox(height: AleraTokens.space12),
        AleraCheckbox(
          value: _plan,
          label: 'Start In Plan Mode',
          enabled: !_opening,
          onChanged: (value) => setState(() => _plan = value),
        ),
      ],
      if (_error case final String error) ...<Widget>[
        const SizedBox(height: AleraTokens.space12),
        AleraInlineNotice(tone: AleraInlineNoticeTone.error, message: error),
      ],
      const SizedBox(height: AleraTokens.space20),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          TextButton(
            onPressed: _opening ? null : _dismiss,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: AleraTokens.space8),
          FilledButton(
            key: const ValueKey<String>('new-agent-chat-create'),
            onPressed: _creating || _reopeningChatId != null
                ? null
                : () => unawaited(_create(selected)),
            child: Text(_creating ? 'Starting' : 'Start Chat'),
          ),
        ],
      ),
      FutureBuilder<List<AgentChatSummary>>(
        future: _archived,
        builder: (context, snapshot) {
          final chats = snapshot.data ?? const <AgentChatSummary>[];
          if (chats.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: AleraTokens.space16),
            child: AgentChatArchivedList(
              chats: chats,
              reopeningChatId: _reopeningChatId,
              onReopen: (chat) => unawaited(_reopen(chat)),
            ),
          );
        },
      ),
    ];
  }
}
