import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/chips/alera_chip.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:alera_mobile/src/features/workbench/presentation/delete_workspace_dialog.dart';
import 'package:alera_mobile/src/features/workbench/presentation/parent_picker_sheet.dart';
import 'package:alera_mobile/src/features/workbench/presentation/sleep_workspace_dialog.dart';
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
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _WorkspaceActionsHeader(workspace: workspace),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: <Widget>[
                  ListTile(
                    leading: const Icon(AleraIcons.edit, size: 20),
                    title: const Text('Rename'),
                    onTap: () =>
                        Navigator.of(context).pop(_WorkspaceAction.rename),
                  ),
                  ListTile(
                    leading: Icon(
                      workspace.isPinned ? AleraIcons.pinOff : AleraIcons.pin,
                      size: 20,
                    ),
                    title: Text(
                      workspace.isPinned ? 'Unpin Workspace' : 'Pin Workspace',
                    ),
                    onTap: () => Navigator.of(context).pop(
                      workspace.isPinned
                          ? _WorkspaceAction.unpin
                          : _WorkspaceAction.pin,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(AleraIcons.tag, size: 20),
                    title: const Text('Manage Tags'),
                    onTap: () =>
                        Navigator.of(context).pop(_WorkspaceAction.tags),
                  ),
                  ListTile(
                    leading: const Icon(AleraIcons.link, size: 20),
                    title: const Text('Set Parent Workspace'),
                    onTap: () => Navigator.of(
                      context,
                    ).pop(_WorkspaceAction.configureParent),
                  ),
                  if (workspace.hasParent)
                    ListTile(
                      leading: const Icon(AleraIcons.close, size: 20),
                      title: const Text('Clear Parent Workspace'),
                      onTap: () => Navigator.of(
                        context,
                      ).pop(_WorkspaceAction.unlinkParent),
                    ),
                  ListTile(
                    leading: const Icon(AleraIcons.external, size: 20),
                    title: const Text('Open in Browser'),
                    onTap: () => Navigator.of(
                      context,
                    ).pop(_WorkspaceAction.openRepository),
                  ),
                  ListTile(
                    leading: const Icon(AleraIcons.copy, size: 20),
                    title: const Text('Copy Path'),
                    onTap: () =>
                        Navigator.of(context).pop(_WorkspaceAction.copyPath),
                  ),
                  ListTile(
                    leading: const Icon(AleraIcons.theme, size: 20),
                    title: const Text('Sleep'),
                    onTap: () =>
                        Navigator.of(context).pop(_WorkspaceAction.sleep),
                  ),
                  if (!workspace.isMain)
                    ListTile(
                      leading: Icon(
                        AleraIcons.delete,
                        size: 20,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      title: Text(
                        'Remove',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      onTap: () =>
                          Navigator.of(context).pop(_WorkspaceAction.delete),
                    ),
                ],
              ),
            ),
          ],
        ),
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
          projects: data.projects,
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
        final confirmed = await showSleepWorkspaceDialog(
          context,
          workspace: workspace,
        );
        if (confirmed) {
          await controller.sleepWorkspace(workspace.id);
        }
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

class _WorkspaceActionsHeader extends StatelessWidget {
  const _WorkspaceActionsHeader({required this.workspace});

  final WorkspaceSummary workspace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final branch = workspace.branch?.trim();
    final tags = _workspaceTagLabels(workspace);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space16,
        AleraTokens.space16,
        AleraTokens.space16,
        AleraTokens.space12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  workspace.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (workspace.isMain) ...<Widget>[
                const SizedBox(width: AleraTokens.space8),
                const Icon(
                  AleraIcons.workspaceMain,
                  size: 16,
                  color: AleraTokens.foregroundMuted,
                ),
              ],
            ],
          ),
          if (branch != null && branch.isNotEmpty) ...<Widget>[
            const SizedBox(height: AleraTokens.space8),
            Row(
              children: <Widget>[
                const Icon(
                  AleraIcons.gitBranch,
                  size: 14,
                  color: AleraTokens.foregroundMuted,
                ),
                const SizedBox(width: AleraTokens.space6),
                Expanded(
                  child: Text(
                    branch,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AleraTokens.foregroundMuted,
                      fontFamily: AleraTokens.monoFontFamily,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (tags.isNotEmpty) ...<Widget>[
            const SizedBox(height: AleraTokens.space8),
            Wrap(
              spacing: AleraTokens.space6,
              runSpacing: AleraTokens.space6,
              children: <Widget>[
                for (final tag in tags)
                  AleraChip(label: tag, leading: AleraIcons.tag),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

List<String> _workspaceTagLabels(WorkspaceSummary workspace) {
  final names = workspace.tagNames
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);
  if (names.isNotEmpty) {
    return names;
  }
  return workspace.tagIds
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toList(growable: false);
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
