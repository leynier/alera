import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_chat/domain/agent_chat_tab.dart';
import 'package:alera/src/features/agent_status/presentation/agent_identity_icon.dart';
import 'package:flutter/material.dart';

/// The mark of a chat's provider, or the generic agent icon for providers
/// Alera has no mark for.
class const AgentChatProviderIcon({
  super.key,
  required final String provider,
  final double size = AleraTokens.iconSm,
  final Color color = AleraTokens.foregroundMuted,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final agentType = agentChatAgentType(provider);
    if (agentType == null) {
      return Icon(AleraIcons.agent, size: size, color: color);
    }
    return ExcludeSemantics(
      child: AgentIdentityIcon(
        agentType: agentType,
        size: size,
        color: color,
        showTooltip: false,
      ),
    );
  }
}
