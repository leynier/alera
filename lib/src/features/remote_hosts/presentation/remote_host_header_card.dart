import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_status_indicator.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/menus/alera_dropdown_entry.dart';
import 'package:alera/src/design_system/surfaces/alera_panel.dart';
import 'package:alera/src/features/remote_hosts/application/remote_host_usage_provider.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/remote_hosts/presentation/remote_host_status_badge.dart';
import 'package:alera/src/shared/format_timestamp.dart';
import 'package:flutter/material.dart';

// Wide enough for the longest label ("Install Runtime", "Connecting…"), so
// the header does not shift while the action changes.
const double _kPrimaryActionMinWidth = 140;

/// The one action the header offers for a host's state.
enum RemoteHostPrimaryAction(final String label) {
  install('Install Runtime'),
  installing('Installing…'),
  connect('Connect'),
  connecting('Connecting…'),
  disconnect('Disconnect'),
  update('Update Runtime');

  bool get enabled => this != installing && this != connecting;
}

/// Null when the runtime cannot do what the state calls for, such as Connect
/// on a runtime without host links.
RemoteHostPrimaryAction? remoteHostPrimaryAction(
  RemoteHostStatus status,
  RemoteHostCapabilities capabilities,
) {
  final link = capabilities.hostLinks;
  return switch (status) {
    RemoteHostNeedsSetup() => RemoteHostPrimaryAction.install,
    RemoteHostInstalling() => RemoteHostPrimaryAction.installing,
    RemoteHostError(origin: RemoteHostErrorOrigin.install) =>
      RemoteHostPrimaryAction.install,
    RemoteHostDisconnected() ||
    RemoteHostOffline() ||
    RemoteHostError() => link ? RemoteHostPrimaryAction.connect : null,
    RemoteHostConnecting() => link ? RemoteHostPrimaryAction.connecting : null,
    RemoteHostConnected(:final updateAvailable)
        when updateAvailable && capabilities.runtimeUpdate =>
      RemoteHostPrimaryAction.update,
    RemoteHostConnected() => link ? RemoteHostPrimaryAction.disconnect : null,
  };
}

enum _HeaderMenuAction { edit, copy, remove }

/// Top of a host's detail: who it is, how it is doing, and what to do next.
class const RemoteHostHeaderCard({
  super.key,
  required final RemoteHostView host,
  required final RemoteHostUsage usage,
  required final RemoteHostCapabilities capabilities,
  required final bool checking,
  required final ValueChanged<RemoteHostPrimaryAction> onPrimaryAction,
  required final VoidCallback? onCheckConnection,
  required final VoidCallback onEditConnection,
  required final VoidCallback onCopySshCommand,
  required final VoidCallback onRemove,

  /// Disables Remove Host and becomes its tooltip.
  final String? removeBlockedReason,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = host.status;
    final action = remoteHostPrimaryAction(status, capabilities);
    final mutedStyle = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final runtimeVersion = switch (status) {
      RemoteHostConnected(:final satelliteVersion?) => satelliteVersion,
      _ => host.target.runtimeVersion,
    };
    final identity = <String>[
      host.address,
      ?host.platformLabel,
      if (runtimeVersion != null) 'Alera runtime $runtimeVersion',
    ].join(' · ');
    final checkedAt = host.target.lastCheckedAt;
    final activity = <String>[
      usage.summary,
      if (checkedAt != null) 'Checked ${formatRelativeTimestamp(checkedAt)}',
    ].join(' · ');
    return AleraPanel(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(AleraTokens.space16),
          child: Column(
            crossAxisAlignment: .stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: .start,
                children: <Widget>[
                  AleraStatusIndicator(
                    icon: remoteHostStatusIcon(status),
                    color: remoteHostStatusColor(status),
                  ),
                  const SizedBox(width: AleraTokens.space12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: .start,
                      children: <Widget>[
                        Wrap(
                          spacing: AleraTokens.space8,
                          runSpacing: AleraTokens.space4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            Text(
                              host.alias,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: AleraTokens.foreground,
                              ),
                            ),
                            RemoteHostStatusBadge(status: status),
                          ],
                        ),
                        const SizedBox(height: AleraTokens.space4),
                        Text(identity, style: mutedStyle),
                        const SizedBox(height: AleraTokens.space2),
                        Text(activity, style: mutedStyle),
                      ],
                    ),
                  ),
                  const SizedBox(width: AleraTokens.space8),
                  _overflowMenu(),
                ],
              ),
              const SizedBox(height: AleraTokens.space12),
              Wrap(
                spacing: AleraTokens.space8,
                runSpacing: AleraTokens.space8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  if (action != null) _primaryButton(action),
                  OutlinedButton(
                    onPressed: checking || host.busy ? null : onCheckConnection,
                    child: Text(checking ? 'Checking…' : 'Check Connection'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _primaryButton(RemoteHostPrimaryAction action) {
    final onPressed = action.enabled && !host.busy
        ? () => onPrimaryAction(action)
        : null;
    final label = Text(action.label, maxLines: 1, overflow: .ellipsis);
    final button = action == RemoteHostPrimaryAction.disconnect
        ? OutlinedButton(onPressed: onPressed, child: label)
        : FilledButton(onPressed: onPressed, child: label);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: _kPrimaryActionMinWidth),
      child: button,
    );
  }

  Widget _overflowMenu() {
    return PopupMenuButton<_HeaderMenuAction>(
      tooltip: 'More Actions',
      icon: const Icon(AleraIcons.more, size: AleraTokens.iconMd),
      onSelected: (action) => switch (action) {
        _HeaderMenuAction.edit => onEditConnection(),
        _HeaderMenuAction.copy => onCopySshCommand(),
        _HeaderMenuAction.remove => onRemove(),
      },
      itemBuilder: (_) => <PopupMenuEntry<_HeaderMenuAction>>[
        AleraDropdownEntry<_HeaderMenuAction>(
          value: _HeaderMenuAction.edit,
          leading: const Icon(AleraIcons.edit, size: AleraTokens.iconMd),
          label: 'Edit Connection',
          enabled: !host.status.isBusy,
        ),
        const AleraDropdownEntry<_HeaderMenuAction>(
          value: _HeaderMenuAction.copy,
          leading: Icon(AleraIcons.copy, size: AleraTokens.iconMd),
          label: 'Copy SSH Command',
        ),
        _RemoveHostEntry(blockedReason: removeBlockedReason),
      ],
    );
  }
}

/// Remove Host in error color, disabled with its reason as tooltip while the
/// host is still in use.
class const _RemoveHostEntry({final String? blockedReason})
    extends PopupMenuEntry<_HeaderMenuAction> {
  @override
  double get height => AleraTokens.space32 + AleraTokens.space4;

  @override
  bool represents(_HeaderMenuAction? value) =>
      blockedReason == null && value == _HeaderMenuAction.remove;

  @override
  State<_RemoveHostEntry> createState() => _RemoveHostEntryState();
}

class _RemoveHostEntryState extends State<_RemoveHostEntry> {
  @override
  Widget build(BuildContext context) {
    final blocked = widget.blockedReason;
    final enabled = blocked == null;
    final color = enabled ? AleraTokens.error : AleraTokens.foregroundFaint;
    final entry = Padding(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space2 / 2),
      child: InkWell(
        onTap: enabled
            ? () => Navigator.of(context).pop(_HeaderMenuAction.remove)
            : null,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        borderRadius: .circular(AleraTokens.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AleraTokens.space8,
            vertical: AleraTokens.space4,
          ),
          child: Row(
            children: <Widget>[
              Icon(AleraIcons.delete, size: AleraTokens.iconMd, color: color),
              const SizedBox(width: AleraTokens.space8),
              Expanded(
                child: Text(
                  'Remove Host',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return enabled ? entry : Tooltip(message: blocked, child: entry);
  }
}
