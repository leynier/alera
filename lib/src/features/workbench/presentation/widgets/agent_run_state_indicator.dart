import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:flutter/material.dart';

/// Visual state glyph for one agent run: spinner while working, state-colored
/// icon otherwise. Shared by the sidebar agent rows and the compact summary.
class AgentRunStateIndicator extends StatelessWidget {
  const AgentRunStateIndicator({
    super.key,
    required this.status,
    this.size = 13,
  });

  final AgentStatusEntry status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final label = agentRunStateLabel(status);
    final color = agentRunStateColor(status);
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: SizedBox.square(
          dimension: size,
          child: Center(child: _buildIndicator(color)),
        ),
      ),
    );
  }

  Widget _buildIndicator(Color color) {
    if (status.state == AgentStatusState.working) {
      return SizedBox.square(
        dimension: size - 2,
        child: CircularProgressIndicator(
          strokeWidth: 1.7,
          color: AleraTokens.warning,
        ),
      );
    }
    final icon = status.interrupted == true
        ? AleraIcons.cancel
        : switch (status.state) {
            AgentStatusState.done => AleraIcons.success,
            AgentStatusState.waiting ||
            AgentStatusState.blocked => AleraIcons.notifications,
            AgentStatusState.working => AleraIcons.sync, // coverage:ignore-line
          };
    return Icon(icon, size: size, color: color);
  }
}

Color agentRunStateColor(AgentStatusEntry status) {
  if (status.interrupted == true) {
    return AleraTokens.error;
  }
  return switch (status.state) {
    AgentStatusState.working => AleraTokens.warning,
    AgentStatusState.waiting => AleraTokens.warning,
    AgentStatusState.blocked => AleraTokens.error,
    AgentStatusState.done => AleraTokens.success,
  };
}

String agentRunStateLabel(AgentStatusEntry status) {
  if (status.interrupted == true) {
    return 'Interrupted';
  }
  return switch (status.state) {
    AgentStatusState.working => 'Working',
    AgentStatusState.waiting => 'Waiting for input',
    AgentStatusState.blocked => 'Blocked',
    AgentStatusState.done => 'Done',
  };
}
