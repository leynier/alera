import 'package:alera/src/features/agent_chat/infra/agent_chat_local_attachment_preparation.dart';
import 'package:alera/src/features/agent_chat/infra/runtime_host_agent_chat_transport.dart';
import 'package:alera/src/features/workbench/application/workbench_controller.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_chat_attachment_preparation.g.dart';

typedef AgentChatPrepareAttachments =
    Future<List<AgentChatAttachment>> Function(
      AgentChatRef chat,
      List<AgentChatAttachment> attachments,
      String clientMessageId,
    );

@riverpod
AgentChatPrepareAttachments agentChatPrepareAttachments(Ref ref) {
  final client = ref.watch(runtimeHostClientProvider);
  return (chat, attachments, clientMessageId) async {
    var localWorkspace = false;
    for (final workspaces
        in ref.read(workbenchControllerProvider).workspacesByProject.values) {
      for (final workspace in workspaces) {
        if (workspace.id == chat.workspaceId) {
          localWorkspace = !workspace.isRemote;
        }
      }
    }
    return AgentChatLocalAttachmentPreparation(
      transport: RuntimeHostAgentChatTransport(client),
      localWorkspace: localWorkspace,
    ).prepare(chat, attachments, clientMessageId);
  };
}
