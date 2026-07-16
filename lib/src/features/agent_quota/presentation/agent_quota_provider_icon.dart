import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:alera/src/features/agent_status/presentation/agent_identity_icon.dart';
import 'package:alera/src/features/settings/domain/alera_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AgentQuotaProviderIcon extends StatelessWidget {
  const AgentQuotaProviderIcon({
    super.key,
    required this.provider,
    this.size = 14,
    this.showTooltip = true,
  });

  final AgentQuotaProviderId provider;
  final double size;
  final bool showTooltip;

  @override
  Widget build(BuildContext context) {
    final agentType = switch (provider) {
      AgentQuotaProviderId.claude => AgentType.claude,
      AgentQuotaProviderId.codex => AgentType.codex,
      AgentQuotaProviderId.grok => AgentType.grok,
      AgentQuotaProviderId.antigravity => AgentType.agy,
      _ => null,
    };
    if (agentType != null) {
      return AgentIdentityIcon(
        agentType: agentType,
        size: size,
        color: AleraTokens.foregroundMuted,
        showTooltip: showTooltip,
      );
    }
    final asset = switch (provider) {
      AgentQuotaProviderId.kimi => 'assets/agents/kimi.svg',
      AgentQuotaProviderId.minimax => 'assets/agents/minimax.svg',
      AgentQuotaProviderId.zai => 'assets/agents/zai.svg',
      _ => throw StateError('Provider icon is not configured: $provider'),
    };
    final icon = Semantics(
      label: provider.label,
      child: SvgPicture.asset(asset, width: size, height: size),
    );
    return showTooltip ? Tooltip(message: provider.label, child: icon) : icon;
  }
}
