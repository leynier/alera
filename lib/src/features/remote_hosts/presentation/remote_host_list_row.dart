import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/design_system/surfaces/alera_active_rail.dart';
import 'package:alera/src/features/remote_hosts/application/remote_host_usage_provider.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_status_badge.dart';
import 'package:flutter/material.dart';

/// One host in the Remote Hosts list: OS icon, alias and status on the first
/// line, address and usage on the second.
class const RemoteHostListRow({
  super.key,
  required final RemoteHostView host,
  required final RemoteHostUsage usage,
  required final bool selected,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraActiveRail(
      active: selected,
      child: Material(
        color: selected ? AleraActiveRail.selectedColor : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AleraTokens.space12),
            child: Row(
              crossAxisAlignment: .start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: AleraTokens.space2),
                  child: AleraHostOsIcon(
                    os: host.os,
                    size: AleraTokens.iconLg,
                    color: selected
                        ? AleraTokens.foreground
                        : AleraTokens.foregroundMuted,
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              host.alias,
                              maxLines: 1,
                              overflow: .ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: AleraTokens.foreground,
                                fontWeight: .w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: AleraTokens.space8),
                          RemoteHostStatusBadge(status: host.status),
                        ],
                      ),
                      const SizedBox(height: AleraTokens.space4),
                      Text(
                        '${host.address} · ${usage.summary}',
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AleraTokens.foregroundMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
