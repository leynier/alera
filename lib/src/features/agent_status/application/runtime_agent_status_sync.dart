import 'dart:async';

import 'package:alera/src/features/agent_status/application/agent_status_controller.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/workbench/infra/terminal_host/terminal_host_protocol.dart';
import 'package:alera/src/shared/infra/runtime/runtime_host_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'runtime_agent_status_sync.g.dart';

@Riverpod(keepAlive: true)
void runtimeAgentStatusSync(Ref ref) {
  final client = ref.watch(runtimeHostClientProvider);
  var disposed = false;

  Future<void> refresh() async {
    try {
      final payload = await client.runtimeRequest('agentPresence.list');
      if (disposed) {
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
    if (event.name == 'agentPresenceChanged' ||
        event.name == aleraRuntimeHostConnectedEvent) {
      unawaited(refresh());
    }
  });
  ref.onDispose(() {
    disposed = true;
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
