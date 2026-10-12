import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_inline_notice.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/remote_hosts/application/remote_host_selection.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:alera/src/features/remote_hosts/domain/remote_host_status.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:flutter/material.dart';

const String workspaceHostNoHostsMessage =
    'Workspaces can also run on another machine over SSH.';

String workspaceHostOfflineMessage(String alias) =>
    '$alias is offline. Alera connects when the workspace needs it.';

/// Where New Workspace runs the workspace: This Device or a remote host.
/// Hosts that cannot take a workspace yet stay listed but disabled, with the
/// reason in parentheses, and the notice under the field says what to do.
class const WorkspaceHostPicker({
  super.key,
  required final String? hostId,
  required final List<RemoteHostView> hosts,
  required final ValueChanged<String?> onChanged,

  /// The project has no checkout on This Device, so only hosts apply.
  final bool remoteOnlyProject = false,
  final bool supportsRemoteSshWorkspaces = true,
  final bool enabled = true,
  final VoidCallback? onAddHost,
  final ValueChanged<String>? onOpenHost,
  final VoidCallback? onOpenRemoteHosts,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final notice = _notice(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        AleraDropdownField<String?>(
          value: normalizedRemoteHostId(hostId),
          labelText: 'Host',
          enabled: enabled,
          filterable: hosts.length > 4,
          filterHintText: 'Search Hosts',
          entries: <AleraDropdownFieldEntry<String?>>[
            AleraDropdownFieldEntry<String?>(
              value: null,
              label: 'This Device',
              leading: const Icon(
                AleraIcons.workspaceMain,
                size: AleraTokens.iconMd,
              ),
              enabled: !remoteOnlyProject,
            ),
            for (final host in hosts)
              AleraDropdownFieldEntry<String?>(
                value: host.id,
                label: host.pickerLabel,
                leading: AleraHostOsIcon(os: host.os, size: AleraTokens.iconMd),
                enabled: supportsRemoteSshWorkspaces && host.status.isReady,
              ),
          ],
          onChanged: onChanged,
        ),
        if (notice != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space8),
          notice,
        ],
      ],
    );
  }

  Widget? _notice(BuildContext context) {
    final remoteId = normalizedRemoteHostId(hostId);
    if (remoteId == null) {
      if (hosts.isEmpty && !remoteOnlyProject) {
        return AleraInlineNotice(
          message: workspaceHostNoHostsMessage,
          child: _action('Add Host', onAddHost),
        );
      }
      if (!supportsRemoteSshWorkspaces && hosts.isNotEmpty) {
        return _HelperText(remoteHostMissingCapabilityMessage());
      }
      return null;
    }
    final error = remoteHostSelectionError(
      hostId: remoteId,
      hosts: hosts,
      supportsRemoteSshWorkspaces: supportsRemoteSshWorkspaces,
    );
    final host = remoteHostViewById(hosts, remoteId);
    final openHost = host == null || onOpenHost == null
        ? null
        : () => onOpenHost!(host.id);
    if (error != null) {
      return AleraInlineNotice(
        message: error,
        tone: .error,
        child: !supportsRemoteSshWorkspaces
            ? null
            : host == null
            ? _action('Open Remote Hosts', onOpenRemoteHosts)
            : _action('Open Host', openHost),
      );
    }
    if (host?.status is RemoteHostOffline) {
      return AleraInlineNotice(
        message: workspaceHostOfflineMessage(host!.alias),
        tone: .warning,
        child: _action('Open Host', openHost),
      );
    }
    return null;
  }

  Widget? _action(String label, VoidCallback? onPressed) {
    if (onPressed == null) {
      return null;
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        child: Text(label),
      ),
    );
  }
}

class const _HelperText(final String text) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: AleraTokens.foregroundMuted),
    );
  }
}
