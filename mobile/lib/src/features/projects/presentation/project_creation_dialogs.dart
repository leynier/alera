import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/features/projects/presentation/remote_directory_picker_screen.dart';
import 'package:flutter/material.dart';

enum AddProjectChoice { existingFolder, cloneRepository }

class CloneProjectDraft {
  const CloneProjectDraft({
    required this.url,
    required this.parentPath,
    required this.directoryName,
    this.projectName,
  });

  final String url;
  final String parentPath;
  final String directoryName;
  final String? projectName;
}

Future<AddProjectChoice?> showAddProjectSheet(BuildContext context) {
  return showModalBottomSheet<AddProjectChoice>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AleraTokens.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('Existing Folder'),
              subtitle: const Text('Register a folder from this host'),
              onTap: () =>
                  Navigator.of(context).pop(AddProjectChoice.existingFolder),
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: const Text('Clone From URL'),
              subtitle: const Text('Clone and register a Git repository'),
              onTap: () =>
                  Navigator.of(context).pop(AddProjectChoice.cloneRepository),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<String?> showOptionalProjectNameDialog(
  BuildContext context,
  String path,
) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Add Project'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            path,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: AleraTokens.monoFontFamily,
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(height: AleraTokens.spaceLg),
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Project Name Optional',
              helperText: 'Leave empty to use the folder name',
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('Add Project'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}

class CloneProjectDialog extends StatefulWidget {
  const CloneProjectDialog({super.key, required this.hostId});

  final String hostId;

  @override
  State<CloneProjectDialog> createState() => _CloneProjectDialogState();
}

class _CloneProjectDialogState extends State<CloneProjectDialog> {
  final _urlController = TextEditingController();
  final _directoryController = TextEditingController();
  final _nameController = TextEditingController();
  String? _parentPath;

  @override
  void dispose() {
    _urlController.dispose();
    _directoryController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _chooseParent() async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => RemoteDirectoryPickerScreen(
          hostId: widget.hostId,
          actionLabel: 'Choose Destination',
        ),
      ),
    );
    if (path != null && mounted) setState(() => _parentPath = path);
  }

  void _deriveDirectory() {
    if (_directoryController.text.trim().isNotEmpty) return;
    final raw = _urlController.text.trim().replaceAll(RegExp(r'[/\\]+$'), '');
    final last = raw.split(RegExp(r'[/\\:]')).last;
    _directoryController.text = last.endsWith('.git')
        ? last.substring(0, last.length - 4)
        : last;
  }

  void _submit() {
    _deriveDirectory();
    final url = _urlController.text.trim();
    final directory = _directoryController.text.trim();
    if (url.isEmpty || directory.isEmpty || _parentPath == null) return;
    Navigator.of(context).pop(
      CloneProjectDraft(
        url: url,
        parentPath: _parentPath!,
        directoryName: directory,
        projectName: _nameController.text.trim().isEmpty
            ? null
            : _nameController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Clone From URL'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _urlController,
              autofocus: true,
              keyboardType: TextInputType.url,
              onChanged: (_) => _deriveDirectory(),
              decoration: const InputDecoration(labelText: 'Git URL'),
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            TextField(
              controller: _directoryController,
              decoration: const InputDecoration(labelText: 'Folder Name'),
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Project Name Optional',
              ),
            ),
            const SizedBox(height: AleraTokens.spaceMd),
            OutlinedButton.icon(
              onPressed: _chooseParent,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(
                _parentPath ?? 'Choose Destination',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Start Clone')),
      ],
    );
  }
}
