import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_host_os_icon.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/projects/domain/remote_project_request.dart';
import 'package:alera/src/features/remote_hosts/application/remote_hosts_state.dart';
import 'package:flutter/material.dart';

/// The fields that describe a project living only on a host: the host, an
/// existing folder there or a repository to clone, and a display name. Hosts
/// that are not ready are listed but cannot be picked. A null
/// [onHostChanged] hides the host picker, for a form opened on one host.
class const RemoteProjectFields({
  super.key,
  required final List<RemoteHostView> hosts,
  required final String? hostId,
  required final RemoteProjectSource source,
  required final ProjectKind kind,
  required final bool enabled,
  required final TextEditingController pathController,
  required final TextEditingController cloneUrlController,
  required final TextEditingController nameController,
  required final ValueChanged<String>? onHostChanged,
  required final ValueChanged<RemoteProjectSource> onSourceChanged,
  required final ValueChanged<ProjectKind> onKindChanged,
  required final VoidCallback onEdited,
  required final VoidCallback onSubmitted,
}) extends StatelessWidget {
  /// A Windows host writes paths with a drive letter, so the example follows
  /// the selected host rather than this device.
  String get _folderHint {
    final selected = hosts.where((host) => host.id == hostId).firstOrNull;
    return selected?.os == HostOs.windows
        ? r'C:\Users\me\project'
        : '/home/me/project';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    final onHostChanged = this.onHostChanged;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Text(
          'The project lives only on the host. Nothing is cloned or copied to this device.',
          style: muted,
        ),
        if (onHostChanged != null) ...<Widget>[
          const SizedBox(height: AleraTokens.space16),
          AleraDropdownField<String>(
            value: hostId,
            labelText: 'Host',
            hintText: 'Select Host',
            enabled: enabled,
            filterable: hosts.length > 4,
            filterHintText: 'Search Hosts',
            entries: <AleraDropdownFieldEntry<String>>[
              for (final host in hosts)
                AleraDropdownFieldEntry<String>(
                  value: host.id,
                  label: host.pickerLabel,
                  enabled: host.status.isReady,
                  leading: AleraHostOsIcon(
                    os: host.os,
                    size: AleraTokens.iconMd,
                  ),
                ),
            ],
            onChanged: onHostChanged,
          ),
        ],
        const SizedBox(height: AleraTokens.space16),
        // The control has no disabled state; a request in flight ignores it.
        IgnorePointer(
          ignoring: !enabled,
          child: AleraSegmentedButton<RemoteProjectSource>(
            selected: source,
            onSelectionChanged: onSourceChanged,
            segments: const <ButtonSegment<RemoteProjectSource>>[
              ButtonSegment<RemoteProjectSource>(
                value: .existingFolder,
                icon: Icon(AleraIcons.folderOpen, size: AleraTokens.iconLg),
                label: Text('Existing Folder'),
              ),
              ButtonSegment<RemoteProjectSource>(
                value: .cloneRepository,
                icon: Icon(AleraIcons.cloudDownload, size: AleraTokens.iconLg),
                label: Text('Clone Repository'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AleraTokens.space12),
        ...switch (source) {
          .existingFolder => <Widget>[
            AleraTextField(
              controller: pathController,
              enabled: enabled,
              labelText: 'Folder on the Host',
              hintText: _folderHint,
              onChanged: (_) => onEdited(),
              onSubmitted: (_) => onSubmitted(),
            ),
            const SizedBox(height: AleraTokens.space12),
            IgnorePointer(
              ignoring: !enabled,
              child: AleraSegmentedButton<ProjectKind>(
                selected: kind,
                onSelectionChanged: onKindChanged,
                segments: const <ButtonSegment<ProjectKind>>[
                  ButtonSegment<ProjectKind>(
                    value: .gitRepository,
                    icon: Icon(
                      AleraIcons.folderSpecial,
                      size: AleraTokens.iconLg,
                    ),
                    label: Text('Git Repository'),
                  ),
                  ButtonSegment<ProjectKind>(
                    value: .folder,
                    icon: Icon(AleraIcons.folder, size: AleraTokens.iconLg),
                    label: Text('Folder'),
                  ),
                ],
              ),
            ),
          ],
          .cloneRepository => <Widget>[
            AleraTextField(
              controller: cloneUrlController,
              enabled: enabled,
              labelText: 'Git URL',
              hintText: 'https://github.com/owner/repository.git',
              onChanged: (_) => onEdited(),
              onSubmitted: (_) => onSubmitted(),
            ),
            const SizedBox(height: AleraTokens.space8),
            Text(
              "The host clones the repository into its own alera-projects folder, with the host's Git credentials.",
              style: muted,
            ),
          ],
        },
        const SizedBox(height: AleraTokens.space12),
        AleraTextField(
          controller: nameController,
          enabled: enabled,
          labelText: 'Display Name (Optional)',
          onChanged: (_) => onEdited(),
          onSubmitted: (_) => onSubmitted(),
        ),
      ],
    );
  }
}

/// The in-place progress of a remote project request.
class const RemoteProjectProgress({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const SizedBox.square(
          dimension: AleraTokens.iconLg,
          child: CircularProgressIndicator(strokeWidth: AleraTokens.strokeSm),
        ),
        const SizedBox(width: AleraTokens.space8),
        Expanded(
          child: Text(
            'Adding the project on the host. A clone can take a few minutes, and closing this dialog does not stop it.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AleraTokens.foregroundMuted),
          ),
        ),
      ],
    );
  }
}
