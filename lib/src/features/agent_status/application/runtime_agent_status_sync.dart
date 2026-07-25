import 'dart:async';

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'runtime_agent_status_sync.g.dart';

const String _agentPresenceCoalesceKey = 'agentPresence';

@Riverpod(keepAlive: true)
void runtimeAgentStatusSync(Ref ref) {
  final client = ref.watch(runtimeHostClientProvider);
  final coalescer = ref.watch(runtimeChangeCoalescerProvider);
  var disposed = false;
  var generation = 0;

  Future<void> refresh() async {
    final requested = ++generation;
    try {
      final payload = await client.runtimeRequest('agentPresence.list');
      // Concurrent refreshes can land out of order, and an older snapshot
      // would undo a newer one.
      if (disposed || requested != generation) {
        return;
      }
      final entries = payload is List
          ? payload
                .whereType<Map>()
                .map(
                  (item) => _entryFromRuntime(Map<String, Object?>.from(item)),
                )
                .whereType<AgentStatusEntry>()
          : const <AgentStatusEntry>[];
      ref
          .read(agentStatusControllerProvider.notifier)
          .replaceRuntimeSnapshot(entries);
    } on Object {
      // Older sidecars keep the existing local status implementation working.
    }
  }

  final subscription = client.runtimeEvents.listen((event) {
    // The host broadcasts one event per hook, so an agent working through a
    // task emits a steady stream of them. Each one costs a full snapshot RPC
    // plus a rebuild of every listener, hence the coalescing.
    if (event.name == 'agentPresenceChanged') {
      coalescer.schedule(_agentPresenceCoalesceKey, refresh);
    } else if (event.name == aleraRuntimeHostConnectedEvent) {
      // Reconnecting means the local snapshot may be stale in either
      // direction, so resync now instead of waiting out the debounce.
      coalescer.cancel(_agentPresenceCoalesceKey);
      unawaited(refresh());
    }
  });
  ref.onDispose(() {
    disposed = true;
    coalescer.cancel(_agentPresenceCoalesceKey);
    unawaited(subscription.cancel());
  });
  unawaited(refresh());
}

AgentStatusEntry? _entryFromRuntime(Map<String, Object?> json) {
  final sessionId = json['handle'];
  final workspaceId = json['workspaceId'];
  final tabId = json['tabId'];
  final agentType = AgentType.values
      .where((value) => value.key == json['agentType'])
      .firstOrNull;
  final state = AgentStatusState.values
      .where((value) => value.key == json['agentState'])
      .firstOrNull;
  if (sessionId is! String ||
      workspaceId is! String ||
      tabId is! String ||
      agentType == null ||
      state == null) {
    return null;
  }
  final updatedAt =
      DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc() ??
      DateTime.now().toUtc();
  final stateStartedAt =
      DateTime.tryParse(json['stateStartedAt'] as String? ?? '')?.toUtc() ??
      updatedAt;
  return AgentStatusEntry(
    terminalSessionId: sessionId,
    workspaceId: workspaceId,
    tabId: tabId,
    agentType: agentType,
    state: state,
    prompt: json['prompt'] as String? ?? '',
    updatedAt: updatedAt,
    stateStartedAt: stateStartedAt,
    toolName: json['toolName'] as String?,
    toolInput: json['toolInput'] as String?,
    lastAssistantMessage: json['lastAssistantMessage'] as String?,
    interrupted: json['interrupted'] as bool?,
  );
}
