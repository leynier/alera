import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:alera_mobile/src/features/workbench/presentation/delete_workspace_dialog.dart';
import 'package:alera_mobile/src/features/workbench/presentation/parent_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _WorkspaceAction { pin, unpin, configureParent, unlinkParent, delete }

/// Long-press actions for one workspace row. Mutating entries only appear
/// when the runtime advertises the mobile mutations capability.
Future<void> showWorkspaceActionsSheet(
  BuildContext context,
  WidgetRef ref, {
  required String hostId,
  required WorkspaceSummary workspace,
  required WorkspaceListData data,
}) async {
  if (!data.supportsMutations) {
    return;
  }
  final action = await showModalBottomSheet<_WorkspaceAction>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          ListTile(
            title: Text(
              workspace.name,
              style: Theme.of(context).textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              workspace.branch ?? workspace.path,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              workspace.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
            ),
            title: Text(workspace.isPinned ? 'Unpin' : 'Pin'),
            onTap: () => Navigator.of(context).pop(
              workspace.isPinned
                  ? _WorkspaceAction.unpin
                  : _WorkspaceAction.pin,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.account_tree_outlined),
            title: const Text('Configure Parent'),
            onTap: () =>
                Navigator.of(context).pop(_WorkspaceAction.configureParent),
          ),
          if (workspace.hasParent)
            ListTile(
              leading: const Icon(Icons.link_off),
              title: const Text('Unlink Parent'),
              onTap: () =>
                  Navigator.of(context).pop(_WorkspaceAction.unlinkParent),
            ),
          if (!workspace.isMain)
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Delete Workspace',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.of(context).pop(_WorkspaceAction.delete),
            ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) {
    return;
  }
  final controller = ref.read(workspaceListControllerProvider(hostId).notifier);
  try {
    switch (action) {
      case _WorkspaceAction.pin:
        await controller.setPinned(workspace.id, true);
      case _WorkspaceAction.unpin:
        await controller.setPinned(workspace.id, false);
      case _WorkspaceAction.configureParent:
        final parentId = await showParentPickerSheet(
          context,
          child: workspace,
          workspaces: data.workspaces,
        );
        if (parentId != null) {
          await controller.linkParent(
            childWorkspaceId: workspace.id,
            parentWorkspaceId: parentId,
          );
        }
      case _WorkspaceAction.unlinkParent:
        await controller.unlinkParent(workspace);
      case _WorkspaceAction.delete:
        await _confirmAndDelete(context, controller, workspace);
    }
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Workspace Action Failed: $error')),
      );
    }
  }
}

Future<void> _confirmAndDelete(
  BuildContext context,
  WorkspaceListController controller,
  WorkspaceSummary workspace,
) async {
  var cascadeCount = 1;
  try {
    cascadeCount = (await controller.cascadePreview(workspace.id)).length;
  } on Object {
    // The preview is advisory; deletion still confirms explicitly.
  }
  if (!context.mounted) {
    return;
  }
  final decision = await showDeleteWorkspaceDialog(
    context,
    workspace: workspace,
    cascadeCount: cascadeCount,
  );
  if (decision == null || !context.mounted) {
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(SnackBar(content: Text('Removing ${workspace.name}')));
  await controller.deleteWorkspace(
    workspace.id,
    deleteBranch: decision.deleteBranch,
  );
  messenger.showSnackBar(SnackBar(content: Text('Removed ${workspace.name}')));
}
