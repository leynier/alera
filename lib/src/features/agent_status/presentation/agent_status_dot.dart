import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_status_dot.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:flutter/material.dart';

class AgentStatusDot extends StatelessWidget {
  const AgentStatusDot({super.key, required this.status, this.size = 7});

  final AgentStatusEntry? status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final entry = status;
    if (entry == null) {
      return const SizedBox.shrink();
    }
    final label = agentStatusTooltip(entry);
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: AleraStatusDot(
          active: true,
          size: size,
          color: agentStatusColor(entry.state),
        ),
      ),
    );
  }
}

Color agentStatusColor(AgentStatusState state) {
  return switch (state) {
    AgentStatusState.working => AleraTokens.info,
    AgentStatusState.waiting => AleraTokens.warning,
    AgentStatusState.blocked => AleraTokens.error,
    AgentStatusState.done => AleraTokens.success,
  };
}

String agentStatusTooltip(AgentStatusEntry entry) {
  final agent = switch (entry.agentType) {
    AgentType.codex => 'Codex',
    AgentType.claude => 'Claude Code',
    AgentType.copilot => 'GitHub Copilot',
    AgentType.cursor => 'Cursor',
    AgentType.agy => 'Antigravity',
    AgentType.opencode => 'OpenCode',
    AgentType.pi => 'Pi',
    AgentType.amp => 'Amp',
  };
  final state = switch (entry.state) {
    AgentStatusState.working => 'working',
    AgentStatusState.waiting => 'waiting',
    AgentStatusState.blocked => 'blocked',
    AgentStatusState.done => entry.interrupted == true ? 'interrupted' : 'done',
  };
  return '$agent $state';
}
