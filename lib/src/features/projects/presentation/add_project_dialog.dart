import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/shared/presentation/toast/alera_toast.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class AddProjectResult {
  const AddProjectResult({required this.repoPath, required this.name});

  final String repoPath;
  final String? name;
}

class AddProjectDialog extends StatefulWidget {
  const AddProjectDialog({super.key});

  @override
  State<AddProjectDialog> createState() => _AddProjectDialogState();
}

class _AddProjectDialogState extends State<AddProjectDialog> {
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  bool _nameTouched = false;

  @override
  void dispose() {
    _pathController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _browse() async {
    try {
      final selected = await getDirectoryPath(
        confirmButtonText: 'Select repository',
      );
      if (!mounted || selected == null || selected.trim().isEmpty) {
        return;
      }
      _pathController.text = selected.trim();
      if (!_nameTouched) {
        _nameController.text = p.basename(selected.trim());
      }
      setState(() {});
    } catch (_) {
      if (!mounted) {
        return;
      }
      AleraToast.show(
        context,
        message: 'Native folder picker is not available; paste path manually.',
        tone: AleraToastTone.info,
      );
    }
  }

  void _submit() {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      return;
    }
    final name = _nameController.text.trim();
    Navigator.of(
      context,
    ).pop(AddProjectResult(repoPath: path, name: name.isEmpty ? null : name));
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
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Choose the git repository folder you want to register.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AleraTokens.space16),
            TextField(
              controller: _pathController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Repository path',
                hintText: '/path/to/git/repository',
                suffixIcon: Tooltip(
                  message: 'Browse',
                  child: IconButton(
                    onPressed: _browse,
                    mouseCursor: SystemMouseCursors.click,
                    icon: const Icon(Icons.folder_open, size: 18),
                  ),
                ),
              ),
              onChanged: (value) {
                if (!_nameTouched) {
                  _nameController.text = p.basename(value.trim());
                }
                setState(() {});
              },
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AleraTokens.space12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Display name (optional)',
              ),
              onChanged: (_) {
                _nameTouched = true;
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _pathController.text.trim().isEmpty ? null : _submit,
          child: const Text('Add project'),
        ),
      ],
    );
  }
}
