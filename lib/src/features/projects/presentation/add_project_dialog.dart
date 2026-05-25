import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/feedback/alera_toast.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

sealed class AddProjectResult {
  const AddProjectResult({required this.name});

  final String? name;
}

class AddLocalProjectResult extends AddProjectResult {
  const AddLocalProjectResult({required this.path, required super.name});

  final String path;
}

class CloneProjectResult extends AddProjectResult {
  const CloneProjectResult({
    required this.gitUrl,
    required this.destinationPath,
    required super.name,
  });

  final String gitUrl;
  final String destinationPath;
}

enum _AddProjectMode { localFolder, cloneFromUrl }

class AddProjectDialog extends StatefulWidget {
  const AddProjectDialog({super.key});

  @override
  State<AddProjectDialog> createState() => _AddProjectDialogState();
}

class _AddProjectDialogState extends State<AddProjectDialog> {
  final TextEditingController _localPathController = TextEditingController();
  final TextEditingController _cloneUrlController = TextEditingController();
  final TextEditingController _cloneDestinationController =
      TextEditingController();
  final TextEditingController _nameController = TextEditingController();

  _AddProjectMode _mode = _AddProjectMode.localFolder;
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
        confirmButtonText: 'Select folder',
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
        confirmButtonText: 'Select parent folder',
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
      tone: AleraToastTone.info,
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
    return AlertDialog(
      title: Row(
        children: <Widget>[
          const Icon(
            Icons.folder_special_outlined,
            size: 18,
            color: AleraTokens.accent,
          ),
          const SizedBox(width: AleraTokens.space8),
          Text('Add project', style: theme.textTheme.titleLarge),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Choose an existing local folder or clone a Git repository from a URL.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: AleraTokens.space16),
              SegmentedButton<_AddProjectMode>(
                segments: const <ButtonSegment<_AddProjectMode>>[
                  ButtonSegment<_AddProjectMode>(
                    value: _AddProjectMode.localFolder,
                    icon: Icon(Icons.folder_open, size: 16),
                    label: Text('Local folder'),
                  ),
                  ButtonSegment<_AddProjectMode>(
                    value: _AddProjectMode.cloneFromUrl,
                    icon: Icon(Icons.cloud_download_outlined, size: 16),
                    label: Text('Clone from URL'),
                  ),
                ],
                selected: <_AddProjectMode>{_mode},
                onSelectionChanged: (selection) =>
                    _selectMode(selection.single),
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
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: const Text('Add project'),
        ),
      ],
    );
  }
}

class _LocalFolderFields extends StatelessWidget {
  const _LocalFolderFields({
    required this.pathController,
    required this.nameController,
    required this.onBrowse,
    required this.onPathChanged,
    required this.onNameChanged,
    required this.onSubmitted,
  });

  final TextEditingController pathController;
  final TextEditingController nameController;
  final VoidCallback onBrowse;
  final ValueChanged<String> onPathChanged;
  final VoidCallback onNameChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Alera will detect whether the folder is a Git repository. Non-Git folders only get a primary workspace.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space12),
        TextField(
          controller: pathController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Project path',
            hintText: '/path/to/project',
            suffixIcon: Tooltip(
              message: 'Browse',
              child: IconButton(
                onPressed: onBrowse,
                mouseCursor: SystemMouseCursors.click,
                icon: const Icon(Icons.folder_open, size: 18),
              ),
            ),
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

class _CloneFromUrlFields extends StatelessWidget {
  const _CloneFromUrlFields({
    required this.urlController,
    required this.destinationController,
    required this.nameController,
    required this.onBrowseParent,
    required this.onUrlChanged,
    required this.onDestinationChanged,
    required this.onNameChanged,
    required this.onSubmitted,
  });

  final TextEditingController urlController;
  final TextEditingController destinationController;
  final TextEditingController nameController;
  final VoidCallback onBrowseParent;
  final ValueChanged<String> onUrlChanged;
  final VoidCallback onDestinationChanged;
  final VoidCallback onNameChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Alera will run git clone into the destination folder and register the cloned repository.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: AleraTokens.foregroundMuted,
          ),
        ),
        const SizedBox(height: AleraTokens.space12),
        TextField(
          controller: urlController,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Git URL',
            hintText: 'https://github.com/owner/repository.git',
          ),
          onChanged: onUrlChanged,
          onSubmitted: (_) => onSubmitted(),
        ),
        const SizedBox(height: AleraTokens.space12),
        TextField(
          controller: destinationController,
          decoration: InputDecoration(
            labelText: 'Destination folder',
            hintText: '/path/to/repository',
            suffixIcon: Tooltip(
              message: 'Choose parent folder',
              child: IconButton(
                onPressed: onBrowseParent,
                mouseCursor: SystemMouseCursors.click,
                icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              ),
            ),
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

class _DisplayNameField extends StatelessWidget {
  const _DisplayNameField({
    required this.controller,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: const InputDecoration(labelText: 'Display name (optional)'),
      onChanged: (_) => onChanged(),
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

class AddProjectProgressDialog extends StatelessWidget {
  const AddProjectProgressDialog({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      content: Row(
        mainAxisSize: MainAxisSize.min,
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
    );
  }
}
