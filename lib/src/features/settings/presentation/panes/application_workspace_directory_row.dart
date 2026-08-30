import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

/// Workspace-directory setting with a Browse picker; commits on blur/submit
/// and maps an empty value back to the platform default (null).
class const WorkspaceDirectoryRow({
  super.key,
  required final String? value,
  required final ValueChanged<String?> onChanged,
}) extends StatefulWidget {
  @override
  State<WorkspaceDirectoryRow> createState() => _WorkspaceDirectoryRowState();
}

class _WorkspaceDirectoryRowState extends State<WorkspaceDirectoryRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value ?? '');
  }

  @override
  void didUpdateWidget(WorkspaceDirectoryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value &&
        (widget.value ?? '') != _controller.text) {
      _controller.text = widget.value ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final next = _controller.text.trim();
    if (next.isEmpty) {
      if (widget.value != null) {
        widget.onChanged(null);
      }
      return;
    }
    if (next != widget.value) {
      widget.onChanged(next);
    }
  }

  Future<void> _browse() async {
    final picked = await getDirectoryPath(
      initialDirectory: _controller.text.isNotEmpty
          ? _controller.text
          : widget.value,
      confirmButtonText: 'Use as workspace directory',
      canCreateDirectories: true,
    );
    if (picked == null) {
      return;
    }
    _controller.text = picked;
    widget.onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AleraTokens.space16),
      child: Column(
        crossAxisAlignment: .start,
        children: <Widget>[
          Text(
            'Workspace Directory',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AleraTokens.foreground,
              fontWeight: .w500,
            ),
          ),
          const SizedBox(height: AleraTokens.space4),
          Text(
            'Where new linked workspaces are created on disk. Existing '
            'workspaces are not moved. Leave empty to use the default '
            '(~/.alera/workspaces).',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AleraTokens.foregroundMuted,
            ),
          ),
          const SizedBox(height: AleraTokens.space12),
          Row(
            crossAxisAlignment: .center,
            children: <Widget>[
              Expanded(
                child: AleraTextField(
                  controller: _controller,
                  onSubmitted: (_) => _commit(),
                  onEditingComplete: _commit,
                  hintText: '~/.alera/workspaces',
                ),
              ),
              const SizedBox(width: AleraTokens.space8),
              OutlinedButton.icon(
                onPressed: _browse,
                icon: const Icon(AleraIcons.folderOpen, size: 16),
                label: const Text('Browse'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
