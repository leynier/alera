import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/remote_hosts/domain/ssh_target.dart';
import 'package:alera/src/features/workbench/domain/remote_workspace.dart';
import 'package:flutter/material.dart';

class const WorkspaceHostPicker({
  super.key,
  required final String? hostId,
  required final List<SshTarget> sshTargets,
  required final ValueChanged<String?> onChanged,
  final bool supportsRemoteSshWorkspaces = true,
  final bool enabled = true,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final helper = _helperText();
    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        AleraDropdownField<String?>(
          value: normalizedRemoteHostId(hostId),
          labelText: 'Host',
          enabled: enabled,
          filterable: sshTargets.length > 4,
          filterHintText: 'Search Hosts',
          entries: <AleraDropdownFieldEntry<String?>>[
            const AleraDropdownFieldEntry<String?>(
              value: null,
              label: 'This Device',
              leading: Icon(AleraIcons.workspaceMain, size: 14),
            ),
            for (final target in sshTargets)
              AleraDropdownFieldEntry<String?>(
                value: target.id,
                label: sshTargetPickerLabel(target),
                leading: const Icon(AleraIcons.host, size: 14),
                enabled: supportsRemoteSshWorkspaces,
              ),
          ],
          onChanged: onChanged,
        ),
        if (helper != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space8),
          Text(
            helper,
            style: theme.textTheme.bodySmall?.copyWith(
              color: _helperIsError
                  ? AleraTokens.error
                  : AleraTokens.foregroundMuted,
            ),
          ),
        ],
      ],
    );
  }

  bool get _helperIsError {
    return remoteWorkspaceHostSelectionError(
          hostId: hostId,
          targets: sshTargets,
          supportsRemoteSshWorkspaces: supportsRemoteSshWorkspaces,
        ) !=
        null;
  }

  String? _helperText() {
    final selectionError = remoteWorkspaceHostSelectionError(
      hostId: hostId,
      targets: sshTargets,
      supportsRemoteSshWorkspaces: supportsRemoteSshWorkspaces,
    );
    if (selectionError != null) {
      return selectionError;
    }
    if (sshTargets.isEmpty) {
      return 'Add SSH hosts in Settings → Remote Hosts to create workspaces on another machine.';
    }
    if (!supportsRemoteSshWorkspaces) {
      return remoteHostMissingCapabilityMessage();
    }
    return null;
  }
}
