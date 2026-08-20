import 'package:alera/src/features/agent_status/domain/agent_status.dart';

const agentStatusIdentityStaleThreshold = Duration(minutes: 30);

class AgentStatusIdentityResolution {
  const AgentStatusIdentityResolution({
    required this.effectiveAgentType,
    required this.inheritedFromActiveTerminal,
    required this.shouldIgnoreEvent,
  });

  final AgentType effectiveAgentType;
  final bool inheritedFromActiveTerminal;
  final bool shouldIgnoreEvent;
}

AgentStatusIdentityResolution resolveAgentStatusIdentity({
  required AgentStatusEntry? previous,
  required AgentType incomingAgentType,
  required AgentStatusState normalizedState,
  required DateTime receivedAt,
  required Duration staleThreshold,
}) {
  final inheritedFromActiveTerminal =
      previous != null &&
      previous.state != AgentStatusState.done &&
      previous.agentType != incomingAgentType &&
      !_isStale(previous, receivedAt, staleThreshold) &&
      // Claude-compat hooks can land first; a later Grok/Cursor event
      // must be able to take over instead of inheriting Claude for 30m.
      !(previous.agentType == AgentType.claude &&
          incomingAgentType != AgentType.claude);
  final effectiveAgentType = inheritedFromActiveTerminal
      ? previous.agentType
      : incomingAgentType;
  return AgentStatusIdentityResolution(
    effectiveAgentType: effectiveAgentType,
    inheritedFromActiveTerminal: inheritedFromActiveTerminal,
    shouldIgnoreEvent:
        inheritedFromActiveTerminal && normalizedState == AgentStatusState.done,
  );
}

bool _isStale(
  AgentStatusEntry entry,
  DateTime receivedAt,
  Duration staleThreshold,
) {
  return receivedAt.difference(entry.updatedAt) > staleThreshold;
}
