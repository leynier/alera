import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> showWorkspaceTagsSheet(
  BuildContext context,
  WidgetRef ref, {
  required String hostId,
  required WorkspaceSummary workspace,
  required WorkspaceListData data,
}) async {
  final selected = ValueNotifier<Set<String>>(<String>{...workspace.tagIds});
  try {
    final action = await showModalBottomSheet<_TagAction>(
      context: context,
      builder: (context) => SafeArea(
        child: ValueListenableBuilder<Set<String>>(
          valueListenable: selected,
          builder: (context, values, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const ListTile(title: Text('Workspace Tags')),
              const Divider(height: 1),
              for (final tag in data.tags)
                CheckboxListTile(
                  value: values.contains(tag.id),
                  title: Text(tag.name),
                  secondary: IconButton(
                    tooltip: 'Delete Tag',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        Navigator.of(context).pop(_TagAction.delete(tag.id)),
                  ),
                  onChanged: (_) {
                    final next = <String>{...values};
                    if (!next.remove(tag.id)) next.add(tag.id);
                    selected.value = next;
                  },
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('New Tag'),
                onTap: () =>
                    Navigator.of(context).pop(const _TagAction.create()),
              ),
              ListTile(
                leading: const Icon(Icons.check),
                title: const Text('Apply Tags'),
                onTap: () =>
                    Navigator.of(context).pop(const _TagAction.apply()),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    final controller = ref.read(
      workspaceListControllerProvider(hostId).notifier,
    );
    switch (action.kind) {
      case _TagActionKind.apply:
        await controller.setTags(workspace.id, selected.value.toList());
      case _TagActionKind.create:
        final name = await _promptForTagName(context);
        if (name != null) {
          final tag = await controller.createTag(name);
          await controller.setTags(
            workspace.id,
            <String>{...selected.value, tag.id}.toList(),
          );
        }
      case _TagActionKind.delete:
        final tag = data.tags.firstWhere((tag) => tag.id == action.tagId);
        if (await _confirmTagDeletion(context, tag.name)) {
          await controller.removeTag(tag.id);
        }
    }
  } finally {
    selected.dispose();
  }
}

Future<bool> _confirmTagDeletion(BuildContext context, String name) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Tag'),
          content: Text('Delete "$name" From All Workspaces?'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ) ??
      false;
}

Future<String?> _promptForTagName(BuildContext context) async {
  final controller = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Tag Name'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isNotEmpty) Navigator.of(context).pop(value);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

enum _TagActionKind { apply, create, delete }

class _TagAction {
  const _TagAction.apply() : kind = _TagActionKind.apply, tagId = null;
  const _TagAction.create() : kind = _TagActionKind.create, tagId = null;
  const _TagAction.delete(this.tagId) : kind = _TagActionKind.delete;

  final _TagActionKind kind;
  final String? tagId;
}
