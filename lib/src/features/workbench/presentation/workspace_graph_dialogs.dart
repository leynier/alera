import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/forms/alera_dropdown_field.dart';
import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:alera/src/design_system/icons/alera_icons.dart';
import 'package:alera/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:alera/src/design_system/layout/alera_dialog.dart';
import 'package:alera/src/features/projects/domain/project.dart';
import 'package:alera/src/features/workbench/application/workspace_graph_repository.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:flutter/material.dart';

class WorkspaceTagSelection {
  const WorkspaceTagSelection({required this.tagIds});

  final Set<String> tagIds;
}

class WorkspaceParentSelection {
  const WorkspaceParentSelection({this.parentWorkspaceId});

  final String? parentWorkspaceId;
}

class WorkspaceParentOption {
  const WorkspaceParentOption({required this.project, required this.workspace});

  final Project project;
  final Workspace workspace;

  String get label {
    final branch = workspace.branch;
    final suffix = branch == null || branch.isEmpty ? '' : ' - $branch';
    return '${project.name} / ${workspace.name}$suffix';
  }
}

Future<WorkspaceTagSelection?> showWorkspaceTagsDialog({
  required BuildContext context,
  required Workspace workspace,
  required List<WorkspaceTag> tags,
  required Future<WorkspaceTag> Function(String name) onCreateTag,
  required Future<void> Function(String tagId) onDeleteTag,
}) {
  return showDialog<WorkspaceTagSelection>(
    context: context,
    builder: (_) => _WorkspaceTagsDialog(
      workspace: workspace,
      tags: tags,
      onCreateTag: onCreateTag,
      onDeleteTag: onDeleteTag,
    ),
  );
}

Future<WorkspaceParentSelection?> showWorkspaceParentDialog({
  required BuildContext context,
  required Workspace workspace,
  required List<WorkspaceParentOption> options,
  required List<WorkspaceRelation> relations,
}) {
  return showDialog<WorkspaceParentSelection>(
    context: context,
    builder: (_) => _WorkspaceParentDialog(
      workspace: workspace,
      options: options,
      relations: relations,
    ),
  );
}

class _WorkspaceTagsDialog extends StatefulWidget {
  const _WorkspaceTagsDialog({
    required this.workspace,
    required this.tags,
    required this.onCreateTag,
    required this.onDeleteTag,
  });

  final Workspace workspace;
  final List<WorkspaceTag> tags;
  final Future<WorkspaceTag> Function(String name) onCreateTag;
  final Future<void> Function(String tagId) onDeleteTag;

  @override
  State<_WorkspaceTagsDialog> createState() => _WorkspaceTagsDialogState();
}

class _WorkspaceTagsDialogState extends State<_WorkspaceTagsDialog> {
  final TextEditingController _tagController = TextEditingController();
  late List<WorkspaceTag> _tags;
  late Set<String> _selectedTagIds;
  bool _creating = false;
  String? _deletingTagId;
  String? _error;

  bool get _busy => _creating || _deletingTagId != null;

  @override
  void initState() {
    super.initState();
    _tags = _sortedTags(widget.tags);
    _selectedTagIds = widget.workspace.tagIds.toSet();
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AleraDialog(
      maxWidth: 460,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(AleraIcons.tag, color: AleraTokens.accent),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    'Manage Tags',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space16),
            if (_tags.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AleraTokens.space12),
                child: Text(
                  'No Tags Created',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _tags.length,
                  itemBuilder: (context, index) {
                    final tag = _tags[index];
                    final selected = _selectedTagIds.contains(tag.id);
                    return CheckboxListTile(
                      value: selected,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      title: Text('#${tag.name}'),
                      secondary: AleraIconButton(
                        tooltip: 'Delete Tag',
                        icon: AleraIcons.delete,
                        onPressed: _busy ? null : () => _deleteTag(tag),
                      ),
                      onChanged: _busy
                          ? null
                          : (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedTagIds.add(tag.id);
                                } else {
                                  _selectedTagIds.remove(tag.id);
                                }
                              });
                            },
                    );
                  },
                ),
              ),
            const SizedBox(height: AleraTokens.space12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: AleraTextField(
                    controller: _tagController,
                    enabled: !_busy,
                    labelText: 'New Tag',
                    errorText: _error,
                    onSubmitted: (_) => _createTag(),
                  ),
                ),
                const SizedBox(width: AleraTokens.space8),
                Padding(
                  padding: const EdgeInsets.only(top: AleraTokens.space8),
                  child: FilledButton(
                    onPressed: _busy ? null : _createTag,
                    child: Text(_creating ? 'Creating…' : 'Create Tag'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(
                  onPressed: _busy
                      ? null
                      : () {
                          Navigator.pop(
                            context,
                            WorkspaceTagSelection(tagIds: _selectedTagIds),
                          );
                        },
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createTag() async {
    final name = _tagController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Tag Name Is Required');
      return;
    }
    if (_tags.any((tag) => tag.name.toLowerCase() == name.toLowerCase())) {
      setState(() => _error = 'Tag Already Exists');
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final tag = await widget.onCreateTag(name);
      if (!mounted) {
        return;
      }
      setState(() {
        _tags = _sortedTags(<WorkspaceTag>[..._tags, tag]);
        _selectedTagIds.add(tag.id);
        _tagController.clear();
        _creating = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _creating = false;
        _error = _userFacingMessage(error);
      });
    }
  }

  Future<void> _deleteTag(WorkspaceTag tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AleraConfirmDialog(
        title: 'Delete Tag',
        message:
            'Delete the tag "#${tag.name}"? It will be removed from every '
            'workspace that uses it.',
        confirmLabel: 'Delete',
        destructive: true,
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _deletingTagId = tag.id;
      _error = null;
    });
    try {
      await widget.onDeleteTag(tag.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _tags = _sortedTags(<WorkspaceTag>[
          for (final candidate in _tags)
            if (candidate.id != tag.id) candidate,
        ]);
        _selectedTagIds.remove(tag.id);
        _deletingTagId = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _deletingTagId = null;
        _error = _userFacingMessage(error);
      });
    }
  }
}

class _WorkspaceParentDialog extends StatefulWidget {
  const _WorkspaceParentDialog({
    required this.workspace,
    required this.options,
    required this.relations,
  });

  final Workspace workspace;
  final List<WorkspaceParentOption> options;
  final List<WorkspaceRelation> relations;

  @override
  State<_WorkspaceParentDialog> createState() => _WorkspaceParentDialogState();
}

class _WorkspaceParentDialogState extends State<_WorkspaceParentDialog> {
  late String? _selectedParentId = _initialParentId();

  String? _initialParentId() {
    final parentId = widget.workspace.parentWorkspaceId;
    if (parentId == null) {
      return null;
    }
    return widget.options.any((option) => option.workspace.id == parentId)
        ? parentId
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final descendants = workspaceDescendantIds(
      widget.workspace.id,
      widget.relations,
    );
    return AleraDialog(
      maxWidth: 460,
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(AleraIcons.link, color: AleraTokens.accent),
                const SizedBox(width: AleraTokens.space8),
                Expanded(
                  child: Text(
                    'Set Parent Workspace',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AleraTokens.space16),
            AleraDropdownField<String?>(
              value: _selectedParentId,
              labelText: 'Parent Workspace',
              filterable: true,
              filterHintText: 'Search Workspaces',
              entries: <AleraDropdownFieldEntry<String?>>[
                const AleraDropdownFieldEntry<String?>(
                  value: null,
                  label: 'No Parent',
                ),
                for (final option in widget.options)
                  if (option.workspace.id != widget.workspace.id)
                    AleraDropdownFieldEntry<String?>(
                      value: option.workspace.id,
                      label: option.label,
                      enabled: !descendants.contains(option.workspace.id),
                    ),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedParentId = value;
                });
              },
            ),
            const SizedBox(height: AleraTokens.space20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: AleraTokens.space8),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(
                      context,
                      WorkspaceParentSelection(
                        parentWorkspaceId: _selectedParentId,
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

List<WorkspaceTag> _sortedTags(List<WorkspaceTag> tags) {
  return <WorkspaceTag>[...tags]
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// Strips the `Exception:` runtime prefix so raw errors read as UI copy.
String _userFacingMessage(Object error) {
  final message = error.toString();
  const prefix = 'Exception: ';
  if (message.startsWith(prefix)) {
    return message.substring(prefix.length);
  }
  return message;
}
