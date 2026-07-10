import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/presentation/agent_status_dot.dart';
import 'package:flutter/material.dart';

/// Session-local acknowledgement of the exact completion epoch a user viewed.
final class WorkbenchTabCompletionAcknowledgements {
  final Map<String, DateTime> _stateStartedAtByTerminal = <String, DateTime>{};

  void acknowledge(AgentStatusEntry? status) {
    if (status?.state != AgentStatusState.done) {
      return;
    }
    _stateStartedAtByTerminal[status!.terminalSessionId] =
        status.stateStartedAt;
  }

  bool isAcknowledged(AgentStatusEntry? status) {
    if (status?.state != AgentStatusState.done) {
      return false;
    }
    return _stateStartedAtByTerminal[status!.terminalSessionId] ==
        status.stateStartedAt;
  }

  void retainTerminalSessions(Set<String> terminalSessionIds) {
    _stateStartedAtByTerminal.removeWhere(
      (sessionId, _) => !terminalSessionIds.contains(sessionId),
    );
  }
}

/// Attention affordance for a workspace tab chip beyond the raw agent state.
enum WorkbenchTabAttention {
  none,
  agentWaiting,
  agentBlocked,
  agentDoneUnacked,
}

/// Derive tab attention: waiting/blocked always need attention; a completion
/// needs attention until its specific state transition has been acknowledged.
WorkbenchTabAttention workbenchTabAttention({
  required AgentStatusEntry? status,
  required bool completionAcknowledged,
}) {
  final entry = status;
  if (entry == null) {
    return WorkbenchTabAttention.none;
  }
  return switch (entry.state) {
    AgentStatusState.waiting => WorkbenchTabAttention.agentWaiting,
    AgentStatusState.blocked => WorkbenchTabAttention.agentBlocked,
    AgentStatusState.done when !completionAcknowledged =>
      WorkbenchTabAttention.agentDoneUnacked,
    AgentStatusState.working ||
    AgentStatusState.done => WorkbenchTabAttention.none,
  };
}

/// Dot color for the tab strip: unacked done uses warning amber.
Color? workbenchTabAttentionDotColor({
  required AgentStatusEntry? status,
  required bool completionAcknowledged,
}) {
  final entry = status;
  if (entry == null) {
    return null;
  }
  final attention = workbenchTabAttention(
    status: entry,
    completionAcknowledged: completionAcknowledged,
  );
  return switch (attention) {
    WorkbenchTabAttention.agentDoneUnacked => AleraTokens.warning,
    WorkbenchTabAttention.none ||
    WorkbenchTabAttention.agentWaiting ||
    WorkbenchTabAttention.agentBlocked => agentStatusColor(entry.state),
  };
}

String workbenchTabAttentionTooltip({
  required AgentStatusEntry status,
  required bool completionAcknowledged,
}) {
  final base = agentStatusTooltip(status);
  if (workbenchTabAttention(
        status: status,
        completionAcknowledged: completionAcknowledged,
      ) ==
      WorkbenchTabAttention.agentDoneUnacked) {
    return '$base (unacked)';
  }
  return base;
}
