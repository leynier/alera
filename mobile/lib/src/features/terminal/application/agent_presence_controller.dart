import 'package:alera_mobile/src/features/runtime/domain/workspace_sidebar_snapshot.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_presence_controller.g.dart';

@riverpod
class AgentPresenceController extends _$AgentPresenceController {
  @override
  Future<List<AgentPresenceSummary>> build(String hostId) async {
    final client = await ref.watch(workspaceClientProvider(hostId).future);
    final subscription = client.events.listen((event) {
      if (event.name == 'agentPresenceChanged') ref.invalidateSelf();
    });
    ref.onDispose(subscription.cancel);
    return client.listAgentPresence();
  }
}
