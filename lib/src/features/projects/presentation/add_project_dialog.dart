import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/buttons/alera_segmented_button.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

sealed class const AddProjectResult({required final String? name});

class const AddLocalProjectResult({
  required final String path,
  required super.name,
}) extends AddProjectResult;

class const CloneProjectResult({
  required final String gitUrl,
  required final String destinationPath,
  required super.name,
}) extends AddProjectResult;

enum _AddProjectMode { localFolder, cloneFromUrl }

class const AddProjectDialog({super.key}) extends StatefulWidget {
  @override
  State<AddProjectDialog> createState() => _AddProjectDialogState();
}

class _AddProjectDialogState extends State<AddProjectDialog> {
  final TextEditingController _localPathController = TextEditingController();
  final TextEditingController _cloneUrlController = TextEditingController();
  final TextEditingController _cloneDestinationController =
      TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  _AddProjectMode _mode = .localFolder;
  bool _nameTouched = false;
  bool _cloneDestinationTouched = false;
  String? _cloneParentDirectory;

  @override
  void dispose() {
    _localPathController.dispose();
    _cloneUrlController.dispose();
    _cloneDestinationController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    return switch (_mode) {
      _AddProjectMode.localFolder =>
        _localPathController.text.trim().isNotEmpty,
      _AddProjectMode.cloneFromUrl =>
        _cloneUrlController.text.trim().isNotEmpty &&
            _cloneDestinationController.text.trim().isNotEmpty,
    };
  }

  Future<void> _browseLocalFolder() async {
    try {
      final selected = await getDirectoryPath(
        confirmButtonText: 'Select Folder',
        canCreateDirectories: true,
      );
      if (!mounted || selected == null || selected.trim().isEmpty) {
        return;
      }
      _localPathController.text = selected.trim();
      if (!_nameTouched) {
        final trimmed = selected.trim();
        _nameController.text = trimmed.isEmpty ? '' : p.basename(trimmed);
      }
      setState(() {});
    } catch (_) {
      _showFolderPickerUnavailable();
    }
  }

  Future<void> _browseCloneParentFolder() async {
    try {
      final selected = await getDirectoryPath(
        confirmButtonText: 'Select Parent Folder',
        canCreateDirectories: true,
      );
      if (!mounted || selected == null || selected.trim().isEmpty) {
        return;
      }
      _cloneParentDirectory = selected.trim();
      _cloneDestinationTouched = false;
      _syncCloneDefaults();
      setState(() {});
    } catch (_) {
      _showFolderPickerUnavailable();
    }
  }

  void _showFolderPickerUnavailable() {
    if (!mounted) {
      return;
    }
    AleraToast.show(
      context,
      message: 'Native folder picker is not available; paste path manually.',
      tone: .info,
    );
  }

  void _selectMode(_AddProjectMode mode) {
    if (_mode == mode) {
      return;
    }
    setState(() {
      _mode = mode;
      if (!_nameTouched) {
        final localPath = _localPathController.text.trim();
        _nameController.text = switch (mode) {
          _AddProjectMode.localFolder =>
            localPath.isEmpty ? '' : p.basename(localPath),
          _AddProjectMode.cloneFromUrl =>
            _repoNameFromGitUrl(_cloneUrlController.text) ?? '',
        };
      }
    });
  }

  void _onLocalPathChanged(String value) {
    if (!_nameTouched) {
      final trimmed = value.trim();
      _nameController.text = trimmed.isEmpty ? '' : p.basename(trimmed);
    }
    setState(() {});
  }

  void _onCloneUrlChanged(String value) {
    _syncCloneDefaults();
    setState(() {});
  }

  void _syncCloneDefaults() {
    final repoName = _repoNameFromGitUrl(_cloneUrlController.text);
    if (!_nameTouched && repoName != null) {
      _nameController.text = repoName;
    }
    final parent = _cloneParentDirectory;
    if (!_cloneDestinationTouched && parent != null && repoName != null) {
      _cloneDestinationController.text = p.join(parent, repoName);
    }
  }

  String? _repoNameFromGitUrl(String value) {
    var url = value.trim();
    if (url.isEmpty) {
      return null;
    }
    final queryIndex = url.indexOf('?');
    if (queryIndex >= 0) {
      url = url.substring(0, queryIndex);
    }
    while (url.endsWith('/') || url.endsWith('\\')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.isEmpty) {
      return null;
    }
    final slashIndex = url.lastIndexOf(RegExp(r'[/\\:]'));
    var name = slashIndex >= 0 ? url.substring(slashIndex + 1) : url;
    if (name.endsWith('.git')) {
      name = name.substring(0, name.length - 4);
    }
    name = name.trim();
    return name.isEmpty ? null : name;
  }

  void _submit() {
    if (!_canSubmit) {
      return;
    }
    final name = _nameController.text.trim();
    final resolvedName = name.isEmpty ? null : name;
    final result = switch (_mode) {
      _AddProjectMode.localFolder => AddLocalProjectResult(
        path: _localPathController.text.trim(),
        name: resolvedName,
      ),
      _AddProjectMode.cloneFromUrl => CloneProjectResult(
        gitUrl: _cloneUrlController.text.trim(),
        destinationPath: _cloneDestinationController.text.trim(),
        name: resolvedName,
      ),
    };
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 600,
      maxHeight: 640,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  AleraIcons.folderSpecial,
                  size: 18,
                  color: AleraTokens.accent,
                ),
                const SizedBox(width: AleraTokens.space8),
                Text('Add Project', style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: AleraTokens.space16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: .min,
                  crossAxisAlignment: .start,
                  children: <Widget>[
                    Text(
                      'Choose an existing local folder or clone a Git repository from a URL.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: AleraTokens.space16),
                    AleraSegmentedButton<_AddProjectMode>(
                      selected: _mode,
                      onSelectionChanged: _selectMode,
                      segments: const <ButtonSegment<_AddProjectMode>>[
                        ButtonSegment<_AddProjectMode>(
                          value: .localFolder,
                          icon: Icon(AleraIcons.folderOpen, size: 16),
                          label: Text('Local Folder'),
                        ),
                        ButtonSegment<_AddProjectMode>(
                          value: .cloneFromUrl,
                          icon: Icon(AleraIcons.cloudDownload, size: 16),
                          label: Text('Clone From URL'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AleraTokens.space16),
                    switch (_mode) {
                      _AddProjectMode.localFolder => _LocalFolderFields(
                        pathController: _localPathController,
                        nameController: _nameController,
                        onBrowse: _browseLocalFolder,
                        onPathChanged: _onLocalPathChanged,
                        onNameChanged: () => _nameTouched = true,
                        onSubmitted: _submit,
                      ),
                      _AddProjectMode.cloneFromUrl => _CloneFromUrlFields(
                        urlController: _cloneUrlController,
                        destinationController: _cloneDestinationController,
                        nameController: _nameController,
                        onBrowseParent: _browseCloneParentFolder,
                        onUrlChanged: _onCloneUrlChanged,
                        onDestinationChanged: () {
                          _cloneDestinationTouched = true;
                          _cloneParentDirectory = null;
                          setState(() {});
                        },
                        onNameChanged: () => _nameTouched = true,
                        onSubmitted: _submit,
                      ),
                    },
                  ],
                ),
              ),
            ),
            const SizedBox(height: AleraTokens.space16),
            Row(
              mainAxisAlignment: .end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(
                  onPressed: _canSubmit ? _submit : null,
                  child: const Text('Add Project'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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

class const AddProjectProgressDialog({super.key, required final String message})
    extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 360,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Row(
          mainAxisSize: .min,
          children: <Widget>[
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AleraTokens.space12),
            Flexible(child: Text(message, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}
