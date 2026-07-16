import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/features/agent_status/domain/agent_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AgentIdentityIcon extends StatelessWidget {
  const AgentIdentityIcon({
    super.key,
    required this.agentType,
    this.size = 14,
    this.color = AleraTokens.foregroundMuted,
    this.showTooltip = true,
  });

  final AgentType agentType;
  final double size;
  final Color color;
  final bool showTooltip;

  @override
  Widget build(BuildContext context) {
    final label = agentDisplayName(agentType);
    final asset = _agentAsset(agentType);
    final icon = Semantics(
      label: label,
      child: asset.raster
          ? Image.asset(
              asset.path,
              width: size,
              height: size,
              filterQuality: FilterQuality.medium,
            )
          : SvgPicture.asset(
              asset.path,
              width: size,
              height: size,
              colorFilter: asset.tintable
                  ? ColorFilter.mode(color, BlendMode.srcIn)
                  : null,
            ),
    );
    return showTooltip ? Tooltip(message: label, child: icon) : icon;
  }
}

class _AgentIconAsset {
  const _AgentIconAsset({
    required this.path,
    this.tintable = true,
    this.raster = false,
  });

  final String path;
  final bool tintable;
  final bool raster;
}

String agentDisplayName(AgentType agentType) {
  return switch (agentType) {
    AgentType.codex => 'Codex',
    AgentType.claude => 'Claude Code',
    AgentType.copilot => 'GitHub Copilot',
    AgentType.cursor => 'Cursor',
    AgentType.agy => 'Antigravity',
    AgentType.opencode => 'OpenCode',
    AgentType.pi => 'Pi',
    AgentType.amp => 'Amp',
    AgentType.grok => 'Grok Build',
  };
}

_AgentIconAsset _agentAsset(AgentType agentType) {
  return switch (agentType) {
    AgentType.codex => const _AgentIconAsset(path: 'assets/agents/codex.svg'),
    AgentType.claude => const _AgentIconAsset(
      path: 'assets/agents/claude.svg',
      tintable: false,
    ),
    AgentType.copilot => const _AgentIconAsset(
      path: 'assets/agents/copilot.svg',
    ),
    AgentType.cursor => const _AgentIconAsset(
      path: 'assets/agents/cursor.png',
      raster: true,
    ),
    AgentType.agy => const _AgentIconAsset(
      path: 'assets/agents/agy.png',
      raster: true,
    ),
    AgentType.opencode => const _AgentIconAsset(
      path: 'assets/agents/opencode.png',
      raster: true,
    ),
    AgentType.pi => const _AgentIconAsset(path: 'assets/agents/pi.svg'),
    AgentType.amp => const _AgentIconAsset(
      path: 'assets/agents/amp.png',
      raster: true,
    ),
    AgentType.grok => const _AgentIconAsset(path: 'assets/agents/grok.svg'),
  };
}
