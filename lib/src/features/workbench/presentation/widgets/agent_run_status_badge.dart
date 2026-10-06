import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/workbench/presentation/widgets/agent_run_state_indicator.dart';
import 'package:flutter/material.dart';

/// Badge label and tone for an agent run, or null when the run needs no label:
/// a working run keeps its spinner and an idle row shows nothing.
(String, AleraBadgeTone)? agentRunStatusBadge(AgentStatusEntry? status) {
  if (status == null) {
    return null;
  }
  if (status.interrupted == true) {
    return ('Interrupted', AleraBadgeTone.error);
  }
  return switch (status.state) {
    AgentStatusState.working => null,
    AgentStatusState.waiting => ('Needs Input', AleraBadgeTone.attention),
    AgentStatusState.blocked => ('Blocked', AleraBadgeTone.error),
    AgentStatusState.done => ('Done', AleraBadgeTone.success),
  };
}

/// Tinted status label for an agent run in a sidebar row. The badge text is
/// the accessible label; the tooltip keeps the longer state description.
class const AgentRunStatusBadge({
  super.key,
  required final AgentStatusEntry? status,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final status = this.status;
    final badge = agentRunStatusBadge(status);
    if (status == null || badge == null) {
      return const SizedBox.shrink();
    }
    final (label, tone) = badge;
    return Tooltip(
      message: agentRunStateLabel(status),
      child: AleraBadge(label: label, tone: tone),
    );
  }
}
