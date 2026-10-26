import 'dart:async';

import 'package:alera/src/app/providers.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_archived_list.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lists the archived chats of [workspace] and reopens the one picked in a
/// new tab of [targetGroupId]. The tab only takes focus while the person is
/// still on [workspace].
Future<void> showAgentChatArchivedChats(
  BuildContext context,
  WidgetRef ref, {
  required Workspace workspace,
  String? targetGroupId,
}) async {
  final result = await showDialog<AgentChatOpenResult>(
    context: context,
    builder: (_) => AgentChatArchivedChatsDialog(workspace: workspace),
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

class const AgentChatArchivedChatsDialog({
  super.key,
  required final Workspace workspace,
}) extends ConsumerStatefulWidget {
  @override
  ConsumerState<AgentChatArchivedChatsDialog> createState() =>
      _AgentChatArchivedChatsDialogState();
}

class _AgentChatArchivedChatsDialogState
    extends ConsumerState<AgentChatArchivedChatsDialog> {
  late final AgentChatReopenIds _reopenIds = AgentChatReopenIds(
    ref.read(agentChatIdGeneratorProvider),
  );
  late Future<List<AgentChatSummary>> _archived = _load();
  String? _reopeningChatId;
  String? _deletingChatId;
  String? _error;

  Future<List<AgentChatSummary>> _load() => loadArchivedAgentChats(
    ref.read(agentChatRepositoryProvider),
    widget.workspace.id,
  );

  void _dismiss() {
    if (_reopeningChatId == null && _deletingChatId == null) {
      Navigator.of(context).pop();
    }
  }

  /// Deleting is permanent, so it asks first; the runtime answers whether
  /// the chat still existed, and either way it leaves the list.
  Future<void> _delete(AgentChatSummary chat) async {
    if (_reopeningChatId != null || _deletingChatId != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Delete ${chat.title.isEmpty ? 'This Chat' : chat.title}?',
        message:
            'The chat and its history are removed from the runtime. This '
            'cannot be undone.',
        confirmLabel: 'Delete Chat',
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _deletingChatId = chat.chatId;
      _error = null;
    });
    try {
      await ref
          .read(agentChatLifecycleRepositoryProvider)
          .delete(
            AgentChatRef(chatId: chat.chatId, workspaceId: chat.workspaceId),
            requestId: _reopenIds.forChat('delete:${chat.chatId}'),
          );
      if (!mounted) return;
      setState(() {
        _deletingChatId = null;
        _archived = _load();
      });
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _deletingChatId = null;
          _error = agentChatErrorMessage(error);
        });
      }
    }
  }

  Future<void> _reopen(AgentChatSummary chat) async {
    if (_reopeningChatId != null || _deletingChatId != null) return;
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

  @override
  Widget build(BuildContext context) {
    final canDelete =
        ref
            .watch(agentChatCapabilityProvider(AgentChatWire.deleteCapability))
            .value ??
        false;
    return PopScope(
      // A reopen in flight must not lose its tab by dismissing.
      canPop: _reopeningChatId == null && _deletingChatId == null,
      child: AleraDialog(
        maxWidth: AleraTokens.dialogCompactWidth,
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AleraDialogHeader(
                title: agentChatArchivedChatsLabel,
                onClose: _dismiss,
              ),
              const SizedBox(height: AleraTokens.space12),
              Flexible(
                child: FutureBuilder<List<AgentChatSummary>>(
                  future: _archived,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return AleraInlineNotice(
                        tone: AleraInlineNoticeTone.error,
                        message: agentChatErrorMessage(snapshot.error!),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () =>
                                setState(() => _archived = _load()),
                            child: const Text(agentChatTryAgainLabel),
                          ),
                        ),
                      );
                    }
                    final chats = snapshot.data;
                    if (chats == null) {
                      return const AleraEmptyState(
                        message: 'Loading archived chats…',
                        loading: true,
                      );
                    }
                    if (chats.isEmpty) {
                      return const AleraEmptyState(
                        message: 'This workspace has no archived chats.',
                      );
                    }
                    return SingleChildScrollView(
                      child: AgentChatArchivedList(
                        chats: chats,
                        reopeningChatId: _reopeningChatId,
                        onReopen: (chat) => unawaited(_reopen(chat)),
                        onDelete: canDelete
                            ? (chat) => unawaited(_delete(chat))
                            : null,
                        deletingChatId: _deletingChatId,
                      ),
                    );
                  },
                ),
              ),
              if (_error case final String error) ...<Widget>[
                const SizedBox(height: AleraTokens.space12),
                AleraInlineNotice(
                  tone: AleraInlineNoticeTone.error,
                  message: error,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
