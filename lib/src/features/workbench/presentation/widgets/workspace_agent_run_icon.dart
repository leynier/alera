import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/agent_status/presentation/agent_identity_icon.dart';
import 'package:alera/src/features/workbench/application/workspace_agent_status_projection.dart';
import 'package:flutter/material.dart';

/// The mark of a workspace agent row: the agent's own mark, or the generic
/// agent icon for a chat provider without one.
class const WorkspaceAgentRunIcon({
  super.key,
  required final WorkspaceAgentRun run,
  final double size = 14,
  final Color color = AleraTokens.foregroundMuted,
  final bool showTooltip = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    if (run.agentType case final type?) {
      return AgentIdentityIcon(
        agentType: type,
        size: size,
        color: color,
        showTooltip: showTooltip,
      );
    }
    final label = agentChatProviderFallbackLabel(run.chat?.provider ?? '');
    final icon = Semantics(
      label: label,
      child: Icon(AleraIcons.agent, size: size, color: color),
    );
    return showTooltip ? Tooltip(message: label, child: icon) : icon;
  }
}
