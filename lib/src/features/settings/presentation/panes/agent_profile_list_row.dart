import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile.dart';
import 'package:alera/src/features/agent_profiles/domain/agent_profile_adapters.dart';
import 'package:alera/src/features/agent_status/presentation/agent_identity_icon.dart';
import 'package:flutter/material.dart';

const double _kSidebarIconSize = 16;

class AgentProfileListRow extends StatelessWidget {
  const AgentProfileListRow({
    super.key,
    required this.profile,
    required this.selected,
    required this.onTap,
    this.isDefault = false,
    this.onSetDefault,
    this.onClone,
  });

  final AgentProfile profile;
  final bool selected;
  final VoidCallback onTap;
  final bool isDefault;
  final VoidCallback? onSetDefault;
  final VoidCallback? onClone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final adapter = agentProfileAdapterFromKey(profile.agentType);
    final launchLabel = profile.launchMode == AgentProfileLaunchMode.managed
        ? 'Managed'
        : 'Command';
    final subtitle = profile.quotaGroup == null
        ? '$launchLabel  ·  ${profile.command}'
        : '$launchLabel  ·  ${profile.command}  ·  ${profile.quotaGroup}';
    return Material(
      color: selected ? AleraTokens.accentSubtle : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        mouseCursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space12),
          child: Row(
            children: <Widget>[
              if (adapter != null)
                AgentIdentityIcon(
                  agentType: adapter,
                  size: _kSidebarIconSize,
                  color: selected
                      ? AleraTokens.foreground
                      : AleraTokens.foregroundMuted,
                  showTooltip: false,
                )
              else
                Icon(
                  Icons.help_outline,
                  size: _kSidebarIconSize,
                  color: AleraTokens.foregroundMuted,
                ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      profile.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AleraTokens.foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AleraTokens.space4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AleraTokens.foregroundMuted,
                      ),
                    ),
                  ],
                ),
              ),
              AleraIconButton(
                tooltip: isDefault ? 'Default Agent Profile' : 'Set As Default',
                icon: AleraIcons.star,
                iconColor: isDefault
                    ? AleraTokens.accent
                    : AleraTokens.foregroundFaint,
                onPressed: onSetDefault,
              ),
              AleraIconButton(
                tooltip: 'Clone Profile',
                icon: AleraIcons.duplicate,
                onPressed: onClone,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
