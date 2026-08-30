import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Agent brand glyph matching the desktop sidebar identity icons.
class const AgentIdentityIcon({
  super.key,
  required final String agentType,
  final double size = 14,
  final Color color = AleraTokens.foregroundMuted,
  final bool showTooltip = true,
}) extends StatelessWidget {
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
              filterQuality: .medium,
            )
          : SvgPicture.asset(
              asset.path,
              width: size,
              height: size,
              colorFilter: asset.tintable
                  ? ColorFilter.mode(color, .srcIn)
                  : null,
            ),
    );
    return showTooltip ? Tooltip(message: label, child: icon) : icon;
  }
}

class const _AgentIconAsset({
  required final String path,
  final bool tintable = true,
  final bool raster = false,
});

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
  'fx' => 'fx',
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
  'fx' => const _AgentIconAsset(path: 'assets/agents/fx.svg'),
  _ => null,
};
