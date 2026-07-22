import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/quotas/presentation/quota_display_labels.dart';
import 'package:alera_mobile/src/features/workbench/presentation/agent_identity_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Provider glyph matching desktop [AgentQuotaProviderIcon].
class AgentQuotaProviderIcon extends StatelessWidget {
  const AgentQuotaProviderIcon({
    super.key,
    required this.provider,
    this.size = 18,
    this.showTooltip = true,
  });

  final String provider;
  final double size;
  final bool showTooltip;

  @override
  Widget build(BuildContext context) {
    final label = quotaProviderDisplayLabel(provider);
    final agentType = switch (provider) {
      'claude' => 'claude',
      'codex' => 'codex',
      'grok' => 'grok',
      'cursor' => 'cursor',
      'antigravity' => 'agy',
      _ => null,
    };
    if (agentType != null) {
      return AgentIdentityIcon(agentType: agentType, size: size);
    }

    final asset = switch (provider) {
      'kimi' => 'assets/agents/kimi.svg',
      'minimax' => 'assets/agents/minimax.svg',
      'zai' => 'assets/agents/zai.svg',
      _ => null,
    };
    final icon = Semantics(
      label: label,
      child: asset == null
          ? Icon(
              Icons.smart_toy_outlined,
              size: size,
              color: AleraTokens.foregroundMuted,
            )
          : SvgPicture.asset(asset, width: size, height: size),
    );
    return showTooltip ? Tooltip(message: label, child: icon) : icon;
  }
}
