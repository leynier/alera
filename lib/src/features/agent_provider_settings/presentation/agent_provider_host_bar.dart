import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/layout/alera_horizontal_scroll_view.dart';
import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/surfaces/hover_container.dart';
import 'package:alera/src/features/agent_provider_settings/application/agent_provider_settings_hosts.dart';
import 'package:flutter/material.dart';

/// Host chips (This Device and each Remote Host) with the host-wide check
/// time and Refresh, above the Providers list.
class const AgentProviderHostBar({
  super.key,
  required final List<AgentProviderHostOption> hosts,
  required final String? selectedHostId,
  required final ValueChanged<String?> onSelect,
  required final String checkedLabel,
  required final bool checking,
  final VoidCallback? onRefresh,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Expanded(
          child: AleraHorizontalScrollView(
            child: Row(
              children: <Widget>[
                for (final host in hosts) ...<Widget>[
                  _HostChip(
                    host: host,
                    selected: host.hostId == selectedHostId,
                    onTap: () => onSelect(host.hostId),
                  ),
                  const SizedBox(width: AleraTokens.space6),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: AleraTokens.space12),
        Text(
          checking ? 'Checking…' : checkedLabel,
          style: theme.textTheme.bodySmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(width: AleraTokens.space8),
        OutlinedButton.icon(
          onPressed: checking ? null : onRefresh,
          icon: checking
              ? const SizedBox.square(
                  dimension: AleraTokens.iconMd,
                  child: CircularProgressIndicator(
                    strokeWidth: AleraTokens.strokeSm,
                  ),
                )
              : const Icon(AleraIcons.refresh, size: AleraTokens.iconMd),
          label: const Text('Refresh'),
        ),
      ],
    );
  }
}

class const _HostChip({
  required final AgentProviderHostOption host,
  required final bool selected,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? AleraTokens.foreground
        : AleraTokens.foregroundMuted;
    final status = host.statusLabel;
    return Semantics(
      button: true,
      selected: selected,
      label: status == null ? host.label : '${host.label}, $status',
      child: HoverContainer(
        onTap: onTap,
        baseColor: selected
            ? AleraTokens.surfaceElevated
            : AleraTokens.surfaceVariant,
        borderRadius: AleraTokens.radiusMd,
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space12,
          vertical: AleraTokens.space6,
        ),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: .min,
            children: <Widget>[
              if (host.hostId == null)
                Icon(AleraIcons.host, size: AleraTokens.iconMd, color: color)
              else
                AleraHostOsIcon(
                  os: host.os,
                  size: AleraTokens.iconMd,
                  color: color,
                ),
              const SizedBox(width: AleraTokens.space6),
              Text(
                host.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: selected ? .w600 : .w500,
                ),
              ),
              if (status != null) ...<Widget>[
                const SizedBox(width: AleraTokens.space6),
                Text(
                  status,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundFaint,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
