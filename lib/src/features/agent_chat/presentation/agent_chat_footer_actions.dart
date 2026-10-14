import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_approval_history.dart';
import 'package:alera/src/features/chat_tasks/application/chat_task_providers.dart';
import 'package:alera/src/features/chat_tasks/presentation/chat_task_chat_actions.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _ChatAction { delegate, sendToChat, approvalHistory, fileCheckpointing }

/// The chat's overflow beside Add Files: Delegate Task and Send To Chat,
/// Approval History, and File Checkpointing, each only where the runtime and
/// the agent offer it. Hidden when none applies.
class const AgentChatActionsMenu({
  super.key,
  required final String chatId,
  required final String workspaceId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    bool capability(String name) =>
        ref.watch(agentChatCapabilityProvider(name)).value ?? false;
    final provider = agentChatControllerProvider(chatId, workspaceId);
    final view = ref.watch(
      provider.select(
        (state) => (
          idle: state.canSwitchProvider,
          checkpointsSupported:
              state
                  .thread
                  ?.session
                  .capabilities
                  .nativeHistory
                  .fileCheckpointing ??
              false,
          checkpointing: state.thread?.session.fileCheckpointing ?? false,
        ),
      ),
    );
    final tasks = ref.watch(chatTasksSupportedProvider).value == true;
    final approvalHistory = capability(AgentChatWire.approvalHistoryCapability);
    final checkpoints =
        view.checkpointsSupported &&
        capability(AgentChatWire.fileCheckpointsCapability);
    if (!tasks && !approvalHistory && !checkpoints) {
      return const SizedBox.shrink();
    }
    return Builder(
      builder: (context) => AleraIconButton(
        key: const ValueKey<String>('agent-chat-actions'),
        tooltip: 'Chat Actions',
        icon: AleraIcons.more,
        onPressed: () => unawaited(
          _open(context, ref, <PopupMenuEntry<_ChatAction>>[
            if (tasks) ...const <PopupMenuEntry<_ChatAction>>[
              AleraDropdownEntry<_ChatAction>(
                value: _ChatAction.delegate,
                label: 'Delegate Task',
              ),
              AleraDropdownEntry<_ChatAction>(
                value: _ChatAction.sendToChat,
                label: 'Send To Chat',
              ),
            ],
            if (approvalHistory)
              const AleraDropdownEntry<_ChatAction>(
                value: _ChatAction.approvalHistory,
                label: 'Approval History',
              ),
            if (checkpoints)
              AleraDropdownEntry<_ChatAction>(
                key: const ValueKey<String>('agent-chat-file-checkpointing'),
                value: _ChatAction.fileCheckpointing,
                label: 'File Checkpointing',
                detail: view.checkpointing ? 'On' : 'Off',
                description: view.idle ? null : 'Available once this turn ends',
                selected: view.checkpointing,
                enabled: view.idle,
              ),
          ], checkpointing: view.checkpointing),
        ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    List<PopupMenuEntry<_ChatAction>> items, {
    required bool checkpointing,
  }) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final action = await showMenu<_ChatAction>(
      context: context,
      position: RelativeRect.fromRect(
        origin & box.size,
        Offset.zero & overlay.size,
      ),
      constraints: const BoxConstraints(minWidth: AleraTokens.contextMenuWidth),
      items: items,
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case _ChatAction.delegate:
        await showDelegateChatTaskFromChat(
          context,
          chatId: chatId,
          workspaceId: workspaceId,
        );
      case _ChatAction.sendToChat:
        await showSendToChatDialog(
          context,
          fromChatId: chatId,
          workspaceId: workspaceId,
        );
      case _ChatAction.approvalHistory:
        final chat = AgentChatRef(chatId: chatId, workspaceId: workspaceId);
        final lifecycle = ref.read(agentChatLifecycleRepositoryProvider);
        await showAgentChatApprovalHistory(
          context,
          load: (before) => lifecycle.approvalHistory(chat, before: before),
        );
      case _ChatAction.fileCheckpointing:
        await _toggleCheckpointing(context, ref, enable: !checkpointing);
    }
  }

  /// Turning checkpoints on says once what they record and where; turning
  /// them off needs no confirmation. Either change restarts the agent's
  /// session with the next message, which is said once it is accepted.
  Future<void> _toggleCheckpointing(
    BuildContext context,
    WidgetRef ref, {
    required bool enable,
  }) async {
    if (enable) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => const AleraConfirmDialog(
          title: 'Turn On File Checkpointing?',
          message:
              'The agent records the files it changes in this workspace, so '
              'rewinding a turn can restore them. Your next message restarts '
              "the agent's session with checkpoints on.",
          confirmLabel: 'Turn On',
        ),
      );
      if (confirmed != true) return;
    }
    final accepted = await ref
        .read(agentChatControllerProvider(chatId, workspaceId).notifier)
        .setFileCheckpointing(enabled: enable);
    if (accepted && !enable) {
      AleraToast.publish(
        message:
            "File checkpointing is off. Your next message restarts the agent's "
            'session.',
      );
    }
  }
}
