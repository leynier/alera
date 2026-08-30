import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:flutter/material.dart';

const double _kSidebarIconSize = 16;

class const RemoteHostListRow({
  super.key,
  required final SshTarget target,
  required final bool selected,
  required final VoidCallback onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? AleraTokens.accentSubtle : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AleraTokens.space12),
          child: Row(
            children: <Widget>[
              Icon(
                AleraIcons.host,
                size: _kSidebarIconSize,
                color: selected
                    ? AleraTokens.foreground
                    : AleraTokens.foregroundMuted,
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    Text(
                      target.alias,
                      maxLines: 1,
                      overflow: .ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AleraTokens.foreground,
                        fontWeight: .w600,
                      ),
                    ),
                    const SizedBox(height: AleraTokens.space4),
                    Text(
                      '${target.username}@${target.host}:${target.port}',
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
    );
  }
}
