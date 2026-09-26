part of 'add_project_dialog.dart';

class const _LocalFolderFields({
  required final TextEditingController pathController,
  required final TextEditingController nameController,
  required final VoidCallback onBrowse,
  required final ValueChanged<String> onPathChanged,
  required final VoidCallback onNameChanged,
  required final VoidCallback onSubmitted,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        Text(
          'Alera will detect whether the folder is a Git repository. Non-Git folders only get a primary workspace.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space12),
        AleraTextField(
          controller: pathController,
          autofocus: true,
          labelText: 'Project Path',
          hintText: '/path/to/project',
          suffix: AleraIconButton(
            tooltip: 'Browse',
            icon: AleraIcons.folderOpen,
            iconSize: 18,
            onPressed: onBrowse,
          ),
          onChanged: onPathChanged,
          onSubmitted: (_) => onSubmitted(),
        ),
        const SizedBox(height: AleraTokens.space12),
        _DisplayNameField(
          controller: nameController,
          onChanged: onNameChanged,
          onSubmitted: onSubmitted,
        ),
      ],
    );
  }
}

class const _CloneFromUrlFields({
  required final TextEditingController urlController,
  required final TextEditingController destinationController,
  required final TextEditingController nameController,
  required final VoidCallback onBrowseParent,
  required final ValueChanged<String> onUrlChanged,
  required final VoidCallback onDestinationChanged,
  required final VoidCallback onNameChanged,
  required final VoidCallback onSubmitted,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: .start,
      children: <Widget>[
        Text(
          'Alera will run git clone into the destination folder and register the cloned repository.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space12),
        AleraTextField(
          controller: urlController,
          autofocus: true,
          labelText: 'Git URL',
          hintText: 'https://github.com/owner/repository.git',
          onChanged: onUrlChanged,
          onSubmitted: (_) => onSubmitted(),
        ),
        const SizedBox(height: AleraTokens.space12),
        AleraTextField(
          controller: destinationController,
          labelText: 'Destination Folder',
          hintText: '/path/to/repository',
          suffix: AleraIconButton(
            tooltip: 'Choose Parent Folder',
            icon: AleraIcons.newFolder,
            iconSize: 18,
            onPressed: onBrowseParent,
          ),
          onChanged: (_) => onDestinationChanged(),
          onSubmitted: (_) => onSubmitted(),
        ),
        const SizedBox(height: AleraTokens.space12),
        _DisplayNameField(
          controller: nameController,
          onChanged: onNameChanged,
          onSubmitted: onSubmitted,
        ),
      ],
    );
  }
}

class const _DisplayNameField({
  required final TextEditingController controller,
  required final VoidCallback onChanged,
  required final VoidCallback onSubmitted,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AleraTextField(
      controller: controller,
      labelText: 'Display Name (Optional)',
      onChanged: (_) => onChanged(),
      onSubmitted: (_) => onSubmitted(),
    );
  }
}
