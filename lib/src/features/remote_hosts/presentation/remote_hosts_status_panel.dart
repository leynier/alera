import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_status_badge.dart';
import 'package:flutter/material.dart';

const double remoteHostsPanelWidth = 300;
const double remoteHostsPanelMaxHeight = 360;

/// The one-click fix a host row in the status bar card offers.
enum RemoteHostQuickAction {
  connect('Connect'),
  retry('Retry'),
  update('Update');

  RemoteHostQuickAction(this.label);

  final String label;
}

/// Null when the state needs nothing, or when the runtime cannot do what it
/// calls for (Connect without host links, Update without runtime updates).
RemoteHostQuickAction? remoteHostQuickAction(
  RemoteHostView host,
  RemoteHostCapabilities capabilities,
) {
  return switch (host.status) {
    RemoteHostDisconnected() || RemoteHostOffline() =>
      capabilities.hostLinks ? RemoteHostQuickAction.connect : null,
    RemoteHostError(:final origin) =>
      origin == RemoteHostErrorOrigin.install || capabilities.hostLinks
          ? RemoteHostQuickAction.retry
          : null,
    RemoteHostConnected(:final updateAvailable) =>
      updateAvailable && capabilities.runtimeUpdate
          ? RemoteHostQuickAction.update
          : null,
    _ => null,
  };
}

/// `Hosts 2/3`, connected over registered, with `· Installing…` while any
/// host installs.
String remoteHostsChipLabel(List<RemoteHostView> hosts) {
  final connected = hosts
      .where((host) => host.status is RemoteHostConnected)
      .length;
  final installing = hosts.any((host) => host.status is RemoteHostInstalling);
  final label = 'Hosts $connected/${hosts.length}';
  return installing ? '$label · Installing…' : label;
}

/// Color of the chip, from the worst host: error, then offline or needs
/// setup, then work in flight, and success only when every host is connected.
Color remoteHostsChipColor(List<RemoteHostView> hosts) {
  var severity = 0;
  for (final host in hosts) {
    if (host.status.severity > severity) {
      severity = host.status.severity;
    }
  }
  if (severity >= 3) {
    return AleraTokens.error;
  }
  if (severity == 2) {
    return AleraTokens.warning;
  }
  if (severity == 0 &&
      hosts.isNotEmpty &&
      hosts.every((host) => host.status is RemoteHostConnected)) {
    return AleraTokens.success;
  }
  return AleraTokens.foregroundMuted;
}

/// Status bar chip summarizing every remote host.
class const RemoteHostsStatusChip({
  super.key,
  required final List<RemoteHostView> hosts,
  required final VoidCallback onPressed,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = remoteHostsChipColor(hosts);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        mouseCursor: WidgetStateMouseCursor.clickable,
        child: Container(
          height: AleraTokens.statusBarHeight,
          padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AleraTokens.borderSubtle)),
          ),
          child: Row(
            mainAxisSize: .min,
            children: <Widget>[
              Icon(
                AleraIcons.host,
                size: AleraTokens.iconStatusBar,
                color: color,
              ),
              const SizedBox(width: AleraTokens.space6),
              Text(
                remoteHostsChipLabel(hosts),
                style: AleraTokens.statusBarTextStyle.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card opened from the remote hosts chip: one row per host with its state
/// and quick fix, and the way into Settings.
class const RemoteHostsStatusPanel({
  super.key,
  required final List<RemoteHostView> hosts,
  required final RemoteHostCapabilities capabilities,
  required final void Function(RemoteHostView host, RemoteHostQuickAction)
  onQuickAction,
  required final ValueChanged<String> onOpenHost,
  required final VoidCallback onOpenRemoteHosts,
  required final VoidCallback onAddHost,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: remoteHostsPanelWidth,
        constraints: const BoxConstraints(maxHeight: remoteHostsPanelMaxHeight),
        decoration: BoxDecoration(
          color: AleraTokens.surfaceElevated,
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          border: Border.all(color: AleraTokens.border),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: AleraTokens.shadowSoft,
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AleraTokens.radiusLg),
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AleraTokens.space12,
                  AleraTokens.space12,
                  AleraTokens.space12,
                  AleraTokens.space4,
                ),
                child: Text('Remote Hosts', style: theme.textTheme.titleSmall),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: .min,
                    crossAxisAlignment: .stretch,
                    children: <Widget>[
                      for (final host in hosts)
                        _HostRow(
                          host: host,
                          action: remoteHostQuickAction(host, capabilities),
                          onAction: (action) => onQuickAction(host, action),
                          onOpen: () => onOpenHost(host.id),
                        ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: AleraTokens.borderSubtle),
              Padding(
                padding: const EdgeInsets.all(AleraTokens.space8),
                child: Wrap(
                  alignment: .end,
                  spacing: AleraTokens.space8,
                  runSpacing: AleraTokens.space8,
                  children: <Widget>[
                    TextButton(
                      onPressed: onAddHost,
                      child: const Text('Add Host'),
                    ),
                    OutlinedButton(
                      onPressed: onOpenRemoteHosts,
                      child: const Text('Open Remote Hosts'),
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

class const _HostRow({
  required final RemoteHostView host,
  required final RemoteHostQuickAction? action,
  required final ValueChanged<RemoteHostQuickAction> onAction,
  required final VoidCallback onOpen,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = this.action;
    return InkWell(
      onTap: onOpen,
      mouseCursor: WidgetStateMouseCursor.clickable,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AleraTokens.space12,
          vertical: AleraTokens.space6,
        ),
        child: Row(
          children: <Widget>[
            AleraHostOsIcon(os: host.os, size: AleraTokens.iconMd),
            const SizedBox(width: AleraTokens.space8),
            Expanded(
              child: Column(
                crossAxisAlignment: .start,
                children: <Widget>[
                  Text(
                    host.alias,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foreground,
                      fontWeight: .w600,
                    ),
                  ),
                  Text(
                    host.address,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AleraTokens.space8),
            RemoteHostStatusBadge(status: host.status),
            if (action != null) ...<Widget>[
              const SizedBox(width: AleraTokens.space4),
              TextButton(
                onPressed: host.busy ? null : () => onAction(action),
                style: TextButton.styleFrom(visualDensity: .compact),
                child: Text(action.label),
              ),
            ],
            const SizedBox(width: AleraTokens.space4),
            Tooltip(
              message: 'Open ${host.alias}',
              child: const Icon(
                AleraIcons.chevronRight,
                size: AleraTokens.iconMd,
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
