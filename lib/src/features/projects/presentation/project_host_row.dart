import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/projects/infra/runtime_project_hosts_client.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_status_badge.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:flutter/material.dart';

/// One host a project is on: where it lives there, its state, how many
/// workspaces use it, and the control that forgets it. [removalBlockedReason]
/// disables that control and becomes its tooltip. [remoteHost] is null for
/// This Device and for a host this app no longer lists; [onOpenHost] makes
/// the row open that host's settings.
class const ProjectHostRow({
  super.key,
  required final ProjectHost host,
  required final RemoteHostView? remoteHost,
  required final String? removalBlockedReason,
  required final bool removing,
  required final VoidCallback? onRemove,
  final VoidCallback? onOpenHost,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLocal = !isRemoteWorkspaceHostId(host.hostId);
    final remoteHost = this.remoteHost;
    final onOpenHost = isLocal ? null : this.onOpenHost;
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AleraTokens.space12,
        vertical: AleraTokens.space8,
      ),
      child: Row(
        children: <Widget>[
          if (isLocal)
            const Icon(
              AleraIcons.workspaceMain,
              size: AleraTokens.iconLg,
              color: AleraTokens.foregroundMuted,
            )
          else
            AleraHostOsIcon(
              os: remoteHost?.os ?? HostOs.unknown,
              size: AleraTokens.iconLg,
            ),
          const SizedBox(width: AleraTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        isLocal
                            ? 'This Device'
                            : remoteHost?.alias ?? host.hostId,
                        maxLines: 1,
                        overflow: .ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AleraTokens.foreground,
                        ),
                      ),
                    ),
                    if (host.primary) ...<Widget>[
                      const SizedBox(width: AleraTokens.space8),
                      const AleraBadge(label: 'Primary'),
                    ],
                    if (remoteHost != null) ...<Widget>[
                      const SizedBox(width: AleraTokens.space8),
                      RemoteHostStatusBadge(status: remoteHost.status),
                    ],
                  ],
                ),
                const SizedBox(height: AleraTokens.space2),
                Text(
                  host.path,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: AleraTokens.monoCompactStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: AleraTokens.space12),
          Text(
            projectHostWorkspaceCountLabel(host.workspaceCount),
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(width: AleraTokens.space8),
          if (removing)
            const SizedBox.square(
              dimension: AleraIconButton.defaultMinSize,
              child: Padding(
                padding: EdgeInsets.all(AleraTokens.space8),
                child: CircularProgressIndicator(
                  strokeWidth: AleraTokens.strokeSm,
                ),
              ),
            )
          else
            AleraIconButton(
              tooltip: removalBlockedReason ?? 'Remove From Host',
              icon: AleraIcons.delete,
              iconColor: removalBlockedReason == null
                  ? AleraTokens.foregroundMuted
                  : AleraTokens.foregroundFaint,
              onPressed: removalBlockedReason == null ? onRemove : null,
            ),
          if (onOpenHost != null)
            AleraIconButton(
              tooltip: 'Open Host',
              icon: AleraIcons.chevronRight,
              iconColor: AleraTokens.foregroundMuted,
              onPressed: onOpenHost,
            ),
        ],
      ),
    );
    if (onOpenHost == null) {
      return row;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onOpenHost, child: row),
    );
  }
}

String projectHostWorkspaceCountLabel(int count) {
  return switch (count) {
    0 => 'No workspaces',
    1 => '1 workspace',
    _ => '$count workspaces',
  };
}
