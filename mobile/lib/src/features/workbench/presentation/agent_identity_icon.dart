import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Agent brand glyph matching the desktop sidebar identity icons.
class AgentIdentityIcon extends StatelessWidget {
  const AgentIdentityIcon({
    super.key,
    required this.agentType,
    this.size = 14,
    this.color = AleraTokens.foregroundMuted,
  });

  final String agentType;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final label = agentDisplayName(agentType);
    final asset = _agentAsset(agentType);
    final icon = Semantics(
      label: label,
      child: asset == null
          ? Icon(Icons.smart_toy_outlined, size: size, color: color)
          : asset.raster
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
    return Tooltip(message: label, child: icon);
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

String agentDisplayName(String agentType) => switch (agentType) {
  'codex' => 'Codex',
  'claude' => 'Claude Code',
  'copilot' => 'GitHub Copilot',
  'cursor' => 'Cursor',
  'agy' => 'Antigravity',
  'opencode' => 'OpenCode',
  'opencode2' => 'OpenCode 2',
  'pi' => 'Pi',
  'amp' => 'Amp',
  'grok' => 'Grok Build',
  _ => 'Agent',
};

_AgentIconAsset? _agentAsset(String agentType) => switch (agentType) {
  'codex' => const _AgentIconAsset(path: 'assets/agents/codex.svg'),
  'claude' => const _AgentIconAsset(
    path: 'assets/agents/claude.svg',
    tintable: false,
  ),
  'copilot' => const _AgentIconAsset(path: 'assets/agents/copilot.svg'),
  'cursor' => const _AgentIconAsset(
    path: 'assets/agents/cursor.png',
    raster: true,
  ),
  'agy' => const _AgentIconAsset(path: 'assets/agents/agy.png', raster: true),
  'opencode' || 'opencode2' => const _AgentIconAsset(
    path: 'assets/agents/opencode.png',
    raster: true,
  ),
  'pi' => const _AgentIconAsset(path: 'assets/agents/pi.svg'),
  'amp' => const _AgentIconAsset(path: 'assets/agents/amp.png', raster: true),
  'grok' => const _AgentIconAsset(path: 'assets/agents/grok.svg'),
  _ => null,
};
