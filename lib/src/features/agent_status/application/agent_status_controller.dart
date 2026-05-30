import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_event_normalizer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'agent_status_controller.g.dart';

abstract interface class AgentStatusSink {
  void applyHookEvent(AgentHookEvent event);
}

@Riverpod(keepAlive: true)
DateTime Function() agentStatusClock(Ref ref) {
  return () => DateTime.now().toUtc();
}

@Riverpod(keepAlive: true)
AgentStatusEntry? agentStatusByTerminalSession(
  Ref ref,
  String terminalSessionId,
) {
  return ref.watch(
    agentStatusControllerProvider.select(
      (entries) => entries[terminalSessionId],
    ),
  );
}

@Riverpod(keepAlive: true)
class AgentStatusController extends _$AgentStatusController
    implements AgentStatusSink {
  late DateTime Function() _now;

  @override
  Map<String, AgentStatusEntry> build() {
    _now = ref.watch(agentStatusClockProvider);
    return const <String, AgentStatusEntry>{};
  }

  @override
  void applyHookEvent(AgentHookEvent event) {
    applyHookEvents(<AgentHookEvent>[event]);
  }

  void applyHookEvents(List<AgentHookEvent> events) {
    if (events.isEmpty) {
      return;
    }
    var next = state;
    var changed = false;
    final receivedAt = _now();
    for (final event in events) {
      if (isAgentSessionCloseHookEvent(event)) {
        if (!next.containsKey(event.terminalSessionId)) {
          continue;
        }
        next = <String, AgentStatusEntry>{...next}
          ..remove(event.terminalSessionId);
        changed = true;
        continue;
      }
      final previous = next[event.terminalSessionId];
      final normalized = normalizeAgentHookEvent(event, previous: previous);
      if (normalized == null) {
        continue;
      }
      final stateStartedAt = previous?.state == normalized.state
          ? previous!.stateStartedAt
          : receivedAt;
      final entry = AgentStatusEntry(
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
      next = <String, AgentStatusEntry>{
        ...next,
        event.terminalSessionId: entry,
      };
      changed = true;
    }
    if (changed) {
      state = next;
    }
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
