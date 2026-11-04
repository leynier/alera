import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/features/agent_chat/domain/agent_chat_composer_draft.dart';

final class const AgentChatDraftSubmission({
  required final String clientMessageId,
  required final AgentChatComposerDraft draft,
  required final DateTime createdAt,
  final String? model,
  final String? reasoningEffort,
  final AgentChatInteractionMode? interactionMode,
  final AgentChatDelivery delivery = AgentChatDelivery.auto,
  final List<AgentChatAttachment>? attachments,
}) {
  AgentChatSendInput input(String chatId, String workspaceId) =>
      AgentChatSendInput(
        chatId: chatId,
        workspaceId: workspaceId,
        clientMessageId: clientMessageId,
        text: draft.text,
        model: model,
        reasoningEffort: reasoningEffort,
        interactionMode: interactionMode,
        delivery: delivery,
        attachments:
            attachments ??
            <AgentChatAttachment>[
              for (final attachment in draft.attachments)
                attachment.toAttachment(),
            ],
      );
}
