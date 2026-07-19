import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:alera_mobile/src/features/workbench/presentation/delete_workspace_dialog.dart';
import 'package:alera_mobile/src/features/workbench/presentation/parent_picker_sheet.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_tags_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

enum _WorkspaceAction {
  rename,
  pin,
  unpin,
  tags,
  configureParent,
  unlinkParent,
  openRepository,
  copyPath,
  sleep,
  delete,
}

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
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Rename Workspace'),
            onTap: () => Navigator.of(context).pop(_WorkspaceAction.rename),
          ),
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
            leading: const Icon(Icons.sell_outlined),
            title: const Text('Tags'),
            onTap: () => Navigator.of(context).pop(_WorkspaceAction.tags),
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
          ListTile(
            leading: const Icon(Icons.open_in_browser),
            title: const Text('Open Repository'),
            onTap: () =>
                Navigator.of(context).pop(_WorkspaceAction.openRepository),
          ),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('Copy Path'),
            onTap: () => Navigator.of(context).pop(_WorkspaceAction.copyPath),
          ),
          ListTile(
            leading: const Icon(Icons.bedtime_outlined),
            title: const Text('Sleep Workspace'),
            onTap: () => Navigator.of(context).pop(_WorkspaceAction.sleep),
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
      case _WorkspaceAction.rename:
        final name = await _promptForWorkspaceName(context, workspace.name);
        if (name != null) await controller.renameWorkspace(workspace.id, name);
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
      case _WorkspaceAction.tags:
        await showWorkspaceTagsSheet(
          context,
          ref,
          hostId: hostId,
          workspace: workspace,
          data: data,
        );
      case _WorkspaceAction.openRepository:
        final remote = await controller.repositoryRemoteUrl(workspace.id);
        final uri = remote == null ? null : _repositoryUri(remote);
        if (uri == null || !await launchUrl(uri)) {
          throw StateError('Repository URL Is Not Available.');
        }
      case _WorkspaceAction.copyPath:
        await Clipboard.setData(ClipboardData(text: workspace.path));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Workspace Path Copied')),
          );
        }
      case _WorkspaceAction.sleep:
        await controller.sleepWorkspace(workspace.id);
      case _WorkspaceAction.delete:
        await _confirmAndDelete(context, controller, workspace, data);
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
  WorkspaceListData data,
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
  final decision = data.confirmWorkspaceRemoval
      ? await showDeleteWorkspaceDialog(
          context,
          workspace: workspace,
          cascadeCount: cascadeCount,
        )
      : DeleteWorkspaceDecision(deleteBranch: !workspace.reusesExistingBranch);
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

Future<String?> _promptForWorkspaceName(
  BuildContext context,
  String currentName,
) async {
  final controller = TextEditingController(text: currentName);
  controller.selection = TextSelection.collapsed(offset: currentName.length);
  try {
    return await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Workspace'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Workspace Name'),
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
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

Uri? _repositoryUri(String remote) {
  var value = remote.trim();
  final scp = RegExp(r'^[^@]+@([^:]+):(.+)$').firstMatch(value);
  if (scp != null) {
    value = 'https://${scp.group(1)}/${scp.group(2)}';
  } else {
    final uri = Uri.tryParse(value);
    if (uri?.scheme == 'ssh' && uri != null) {
      value = 'https://${uri.host}${uri.path}';
    }
  }
  if (value.endsWith('.git')) value = value.substring(0, value.length - 4);
  final uri = Uri.tryParse(value);
  return uri != null && uri.hasScheme ? uri : null;
}
