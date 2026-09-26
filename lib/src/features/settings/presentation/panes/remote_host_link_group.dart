import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_settings_group.dart';
import 'package:alera/src/features/remote_hosts/domain/host_link.dart';
import 'package:flutter/material.dart';

/// Settings group showing the hub's persistent link to the selected host.
///
/// [state] is null while the runtime has never tried this host. [onConnect]
/// and [onDisconnect] are null when the host is not bootstrapped or a link
/// operation is in flight.
class const RemoteHostLinkGroup({
  super.key,
  required final HostLinkState? state,
  required final bool busy,
  required final VoidCallback? onConnect,
  required final VoidCallback? onDisconnect,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phase = state?.phase ?? HostLinkPhase.disconnected;
    final attachment = state?.attachment;
    final error = state?.error;
    final detail = switch (phase) {
      HostLinkPhase.attached when attachment != null =>
        'Satellite runtime ${attachment.hostVersion ?? 'unknown'} on ${attachment.platform}/${attachment.arch}',
      HostLinkPhase.attached => 'Satellite runtime attached',
      HostLinkPhase.connecting => 'Opening the ssh session',
      HostLinkPhase.failed => error ?? 'The link failed',
      HostLinkPhase.disconnected =>
        'Opened on demand when a remote workspace needs the host',
    };
    return AleraSettingsGroup(
      title: 'Host Link',
      description: 'One persistent ssh session carries files, Git, search and terminals for every workspace on this host.',
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AleraTokens.space12),
          child: Row(
            children: <Widget>[
              Icon(
                _phaseIcon(phase),
                size: AleraTokens.iconSm,
                color: _phaseColor(phase),
              ),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Column(
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    Text(
                      hostLinkPhaseLabel(phase),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: AleraTokens.foreground,
                        fontWeight: .w600,
                      ),
                    ),
                    const SizedBox(height: AleraTokens.space4),
                    Text(
                      detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: phase == HostLinkPhase.failed
                            ? AleraTokens.error
                            : AleraTokens.foregroundMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AleraTokens.space12),
              if (phase == HostLinkPhase.attached)
                OutlinedButton.icon(
                  onPressed: busy ? null : onDisconnect,
                  icon: Icon(busy ? AleraIcons.loading : AleraIcons.unlink),
                  label: const Text('Disconnect'),
                )
              else
                OutlinedButton.icon(
                  onPressed: busy || phase == HostLinkPhase.connecting
                      ? null
                      : onConnect,
                  icon: Icon(
                    busy || phase == HostLinkPhase.connecting
                        ? AleraIcons.loading
                        : AleraIcons.link,
                  ),
                  label: const Text('Connect'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String hostLinkPhaseLabel(HostLinkPhase phase) {
  return switch (phase) {
    HostLinkPhase.disconnected => 'Not connected',
    HostLinkPhase.connecting => 'Connecting',
    HostLinkPhase.attached => 'Attached',
    HostLinkPhase.failed => 'Failed',
  };
}

IconData _phaseIcon(HostLinkPhase phase) {
  return switch (phase) {
    HostLinkPhase.attached => AleraIcons.success,
    HostLinkPhase.connecting => AleraIcons.loading,
    HostLinkPhase.failed => AleraIcons.error,
    HostLinkPhase.disconnected => AleraIcons.host,
  };
}

Color _phaseColor(HostLinkPhase phase) {
  return switch (phase) {
    HostLinkPhase.attached => AleraTokens.success,
    HostLinkPhase.failed => AleraTokens.error,
    HostLinkPhase.connecting ||
    HostLinkPhase.disconnected => AleraTokens.foregroundMuted,
  };
}
