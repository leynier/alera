import 'package:alera/src/design_system/chat/alera_message_editor.dart';
import 'package:alera/src/design_system/chat/alera_message_queue.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_controller.dart';
import 'package:alera/src/features/agent_chat/application/agent_chat_providers.dart';
import 'package:alera/src/features/agent_chat/presentation/agent_chat_surface_history.dart';
import 'package:alera/src/features/workbench/presentation/terminal_composer_controller.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Messages the runtime holds until the running turn ends. Every client sees
/// the same queue. Edit replaces the text in one runtime step where the
/// runtime offers it, and otherwise takes the message back into the
/// composer. Steer moves a message into the running turn, only where the
/// runtime does that atomically and the agent accepts steering.
class const AgentChatFooterQueue({
  super.key,
  required final String chatId,
  required final String workspaceId,
  required final List<AgentChatQueueEntry> queue,
  required final bool canSteer,
  required final TerminalComposerController composer,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(
      agentChatControllerProvider(chatId, workspaceId).notifier,
    );
    final editInPlace =
        ref
            .watch(
              agentChatCapabilityProvider(AgentChatWire.queueEditCapability),
            )
            .value ??
        false;
    final steerSupported =
        ref
            .watch(
              agentChatCapabilityProvider(AgentChatWire.queueSteerCapability),
            )
            .value ??
        false;
    AgentChatQueueEntry? entryFor(String queueId) =>
        queue.where((entry) => entry.queueId == queueId).firstOrNull;
    return AleraMessageQueue(
      key: const ValueKey<String>('agent-chat-queue'),
      messages: <AleraQueuedMessageRow>[
        for (final entry in queue)
          AleraQueuedMessageRow(
            id: entry.queueId,
            text: entry.text,
            attachmentCount: entry.attachments.length,
            hasImage: entry.attachments.any(
              (attachment) => attachment.type.isImage,
            ),
          ),
      ],
      canSteer: canSteer && steerSupported,
      onSteer: controller.steerQueued,
      onRemove: (queueId) async => controller.cancelQueued(queueId),
      onEdit: (queueId) async {
        final entry = entryFor(queueId);
        if (entry == null) return;
        if (editInPlace) {
          await showDialog<void>(
            context: context,
            builder: (_) => AleraMessageEditor(
              text: entry.text,
              attachmentCount: entry.attachments.length,
              onSave: (text) => controller.editQueued(queueId, text),
            ),
          );
          return;
        }
        if (await controller.cancelQueued(queueId)) _restore(entry);
      },
    );
  }

  /// Puts a message taken back from the queue into the composer, after any
  /// draft already there.
  void _restore(AgentChatQueueEntry entry) {
    if (appendAgentChatDraft(composer, entry.text, entry.attachments)) {
      AleraToast.publish(
        message: 'The queued message was added to your draft.',
      );
    }
  }
}
