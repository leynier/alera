import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_profiles/infra/runtime_agent_profile_repository.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_profile_providers.g.dart';

@Riverpod(keepAlive: true)
RuntimeAgentProfileRepository agentProfileRepository(Ref ref) {
  return RuntimeAgentProfileRepository(
    ref.watch(runtimeHostClientProvider),
    coalescer: ref.watch(runtimeChangeCoalescerProvider),
  );
}

@Riverpod(keepAlive: true)
Stream<List<AgentProfile>> agentProfiles(Ref ref) {
  return ref.watch(agentProfileRepositoryProvider).watchAll();
}
