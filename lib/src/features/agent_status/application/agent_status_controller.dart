import 'package:alera/src/features/agent_status/application/agent_hook_lifecycle_guard.dart';
import 'package:alera/src/features/agent_status/application/agent_status_identity_resolver.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/infra/agent_hook_event_normalizer.dart';
import 'package:flutter/foundation.dart';
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
  final AgentHookLifecycleGuard _lifecycleGuard = AgentHookLifecycleGuard();

  /// When a terminal was cleared locally, so a stale host snapshot cannot
  /// bring its status back.
  final Map<String, DateTime> _clearedAt = <String, DateTime>{};

  @override
  Map<String, AgentStatusEntry> build() {
    _lifecycleGuard.reset();
    _clearedAt.clear();
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
      if (!_lifecycleGuard.shouldApply(event)) {
        continue;
      }
      final previous = next[event.terminalSessionId];
      if (isAgentSessionResetHookEvent(event)) {
        if (previous == null) {
          continue;
        }
        next = <String, AgentStatusEntry>{...next}
          ..remove(event.terminalSessionId);
        changed = true;
        continue;
      }
      if (isAgentSessionCloseHookEvent(event)) {
        final identity = resolveAgentStatusIdentity(
          previous: previous,
          incomingAgentType: event.agentType,
          normalizedState: .done,
          receivedAt: receivedAt,
          staleThreshold: agentStatusIdentityStaleThreshold,
        );
        if (identity.shouldIgnoreEvent || previous == null) {
          continue;
        }
        next = <String, AgentStatusEntry>{...next}
          ..remove(event.terminalSessionId);
        changed = true;
        continue;
      }
      final normalized = normalizeAgentHookEvent(event, previous: previous);
      if (normalized == null) {
        continue;
      }
      final identity = resolveAgentStatusIdentity(
        previous: previous,
        incomingAgentType: event.agentType,
        normalizedState: normalized.state,
        receivedAt: receivedAt,
        staleThreshold: agentStatusIdentityStaleThreshold,
      );
      if (identity.shouldIgnoreEvent) {
        continue;
      }
      final stateStartedAt = previous?.state == normalized.state
          ? previous!.stateStartedAt
          : receivedAt;
      final entry = AgentStatusEntry(
        terminalSessionId: event.terminalSessionId,
        workspaceId: event.workspaceId,
        tabId: event.tabId,
        agentType: identity.effectiveAgentType,
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
        state: .done,
        updatedAt: receivedAt,
        stateStartedAt: receivedAt,
        lastAssistantMessage: 'Terminal exited with code $exitCode.',
        interrupted: null,
      );
    }
    state = next;
  }

  void clearTerminal(String terminalSessionId) {
    _lifecycleGuard.clearTerminal(terminalSessionId);
    _clearedAt[terminalSessionId] = _now();
    if (!state.containsKey(terminalSessionId)) {
      return;
    }
    final next = <String, AgentStatusEntry>{...state}
      ..remove(terminalSessionId);
    state = next;
  }

  /// Drops every in-memory status entry for a workspace (e.g. after delete).
  void clearWorkspace(String workspaceId) {
    _lifecycleGuard.clearWorkspace(workspaceId);
    final clearedAt = _now();
    final next = <String, AgentStatusEntry>{};
    for (final entry in state.entries) {
      if (entry.value.workspaceId == workspaceId) {
        _clearedAt[entry.key] = clearedAt;
      } else {
        next[entry.key] = entry.value;
      }
    }
    if (next.length == state.length) {
      return;
    }
    state = next;
  }

  /// Merges the host's presence snapshot over local state.
  ///
  /// The host keeps a `working` presence for the life of the PTY when a
  /// terminating hook never arrives, so a plain replace would resurrect runs
  /// that [markTerminalExited] or [clearTerminal] already resolved and leave
  /// them spinning forever. A locally resolved run therefore wins until the
  /// host reports something genuinely newer.
  void replaceRuntimeSnapshot(Iterable<AgentStatusEntry> entries) {
    final next = <String, AgentStatusEntry>{};
    final reported = <String>{};
    for (final entry in entries) {
      reported.add(entry.terminalSessionId);
      final sessionId = entry.terminalSessionId;
      if (_clearedAt[sessionId] case final clearedAt?) {
        if (!entry.updatedAt.isAfter(clearedAt)) {
          continue;
        }
        _clearedAt.remove(sessionId);
      }
      final previous = state[sessionId];
      final resolvedLocally =
          previous != null &&
          previous.state == AgentStatusState.done &&
          entry.state != AgentStatusState.done &&
          !entry.updatedAt.isAfter(previous.updatedAt);
      next[sessionId] = resolvedLocally ? previous : entry;
    }
    // Only forget a local clear once the host stops reporting that session,
    // otherwise the very next snapshot would resurrect what was cleared.
    _clearedAt.removeWhere((sessionId, _) => !reported.contains(sessionId));
    if (mapEquals(next, state)) {
      return;
    }
    state = next;
  }
}
