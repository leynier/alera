part of 'add_remote_project_dialog.dart';

class const _RemoteProjectFields({
  required final List<SshTarget> hosts,
  required final String? hostId,
  required final RemoteProjectSource source,
  required final ProjectKind kind,
  required final bool enabled,
  required final TextEditingController pathController,
  required final TextEditingController cloneUrlController,
  required final TextEditingController nameController,
  required final ValueChanged<String> onHostChanged,
  required final ValueChanged<RemoteProjectSource> onSourceChanged,
  required final ValueChanged<ProjectKind> onKindChanged,
  required final VoidCallback onEdited,
  required final VoidCallback onSubmitted,
}) extends StatelessWidget {
  /// A Windows host writes paths with a drive letter, so the example follows
  /// the selected host rather than this device.
  String get _folderHint {
    final selected = sshTargetsById(hosts)[hostId];
    return sshTargetHostOs(selected) == HostOs.windows
        ? r'C:\Users\me\project'
        : '/home/me/project';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: AleraTokens.foregroundMuted,
    );
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: <Widget>[
        Text(
          'The project lives only on the host. Nothing is cloned or copied to this device.',
          style: muted,
        ),
        const SizedBox(height: AleraTokens.space16),
        AleraDropdownField<String>(
          value: hostId,
          labelText: 'Host',
          hintText: 'Select Host',
          enabled: enabled,
          filterable: hosts.length > 4,
          filterHintText: 'Search Hosts',
          entries: <AleraDropdownFieldEntry<String>>[
            for (final target in hosts)
              AleraDropdownFieldEntry<String>(
                value: target.id,
                label: sshTargetPickerLabel(target),
                leading: AleraHostOsIcon(
                  os: sshTargetHostOs(target),
                  size: AleraTokens.iconMd,
                ),
              ),
          ],
          onChanged: onHostChanged,
        ),
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

class const _RemoteProjectProgress() extends StatelessWidget {
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
