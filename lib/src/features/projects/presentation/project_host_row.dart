import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/badges/alera_badge.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/projects/infra/runtime_project_hosts_client.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target_host_os.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:flutter/material.dart';

/// One host a project is on: where it lives there, how many workspaces use
/// it, and the control that forgets it. [removalBlockedReason] disables that
/// control and becomes its tooltip.
class const ProjectHostRow({
  super.key,
  required final ProjectHost host,
  required final SshTarget? target,
  required final String? removalBlockedReason,
  required final bool removing,
  required final VoidCallback? onRemove,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLocal = !isRemoteWorkspaceHostId(host.hostId);
    return Padding(
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
              os: sshTargetHostOs(target),
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
                        isLocal ? 'This Device' : target?.alias ?? host.hostId,
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
        ],
      ),
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
