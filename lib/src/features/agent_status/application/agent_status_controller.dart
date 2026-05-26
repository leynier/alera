import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_event_normalizer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class AgentStatusSink {
  void applyHookEvent(AgentHookEvent event);
}

final agentStatusClockProvider = Provider<DateTime Function()>((ref) {
  return () => DateTime.now().toUtc();
});

final agentStatusControllerProvider =
    NotifierProvider<AgentStatusController, Map<String, AgentStatusEntry>>(
      AgentStatusController.new,
    );

final agentStatusByTerminalSessionProvider =
    Provider.family<AgentStatusEntry?, String>((ref, terminalSessionId) {
      return ref.watch(
        agentStatusControllerProvider.select(
          (entries) => entries[terminalSessionId],
        ),
      );
    });

class AgentStatusController extends Notifier<Map<String, AgentStatusEntry>>
    implements AgentStatusSink {
  late DateTime Function() _now;

  @override
  Map<String, AgentStatusEntry> build() {
    _now = ref.watch(agentStatusClockProvider);
    return const <String, AgentStatusEntry>{};
  }

  @override
  void applyHookEvent(AgentHookEvent event) {
    final previous = state[event.terminalSessionId];
    final normalized = normalizeAgentHookEvent(event, previous: previous);
    if (normalized == null) {
      return;
    }
    final receivedAt = _now();
    final stateStartedAt = previous?.state == normalized.state
        ? previous!.stateStartedAt
        : receivedAt;
    final next = AgentStatusEntry(
      terminalSessionId: event.terminalSessionId,
      workspaceId: event.workspaceId,
      tabId: event.tabId,
      agentType: event.agentType,
      state: normalized.state,
      prompt: normalized.prompt,
      updatedAt: receivedAt,
      stateStartedAt: stateStartedAt,
      toolName: normalized.toolName,
      toolInput: normalized.toolInput,
      lastAssistantMessage: normalized.lastAssistantMessage,
      interrupted: normalized.interrupted,
    );
    state = <String, AgentStatusEntry>{...state, event.terminalSessionId: next};
  }

  void markTerminalExited({
    required String workspaceId,
    required String tabId,
    required int exitCode,
  }) {
    final current = state.values.where(
      (entry) =>
          entry.workspaceId == workspaceId &&
          entry.tabId == tabId &&
          entry.state != AgentStatusState.done,
    );
    if (current.isEmpty) {
      return;
    }
    final receivedAt = _now();
    final next = <String, AgentStatusEntry>{...state};
    for (final entry in current) {
      next[entry.terminalSessionId] = entry.copyWith(
        state: AgentStatusState.done,
        updatedAt: receivedAt,
        stateStartedAt: receivedAt,
        lastAssistantMessage: 'Terminal exited with code $exitCode.',
        interrupted: null,
      );
    }
    state = next;
  }

  void clearTerminal(String terminalSessionId) {
    if (!state.containsKey(terminalSessionId)) {
      return;
    }
    final next = <String, AgentStatusEntry>{...state}
      ..remove(terminalSessionId);
    state = next;
  }
}
