import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';

const agentTitleCapability = 'aiTextAgentTitleV1';

class const AgentTitleService(final RuntimeHostClient client) {
  Future<bool> isAvailable() async {
    final status = await client.runtimeRequest('status.get');
    return status is Map &&
        status['runtimeCapabilities'] is List &&
        (status['runtimeCapabilities'] as List).contains(agentTitleCapability);
  }

  Future<void> generate(WorkspaceTabRecord tab) async {
    await client.runtimeRequest('aiText.agentTitle.generate', <String, Object?>{
      'tabId': tab.id,
      'expectedConversationId': tab.payload['agentTitleConversationId'],
      'expectedRevision': tab.payload['agentTitleRevision'],
    }, const Duration(minutes: 11));
  }
}
