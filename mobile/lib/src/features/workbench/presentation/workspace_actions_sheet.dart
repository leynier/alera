import 'package:alera_mobile/src/features/workbench/presentation/section_picker_sheet.dart';
import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/chips/alera_chip.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/linked_issues/application/linked_issues_controller.dart';
import 'package:alera_mobile/src/features/linked_issues/presentation/mobile_link_issue_dialog.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_host.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_section_summary.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_hosts_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_list_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_listing_tree.dart';
import 'package:alera_mobile/src/features/workbench/presentation/parent_picker_sheet.dart';
import 'package:alera_mobile/src/features/workbench/presentation/archive_workspace_dialog.dart';
import 'package:alera_mobile/src/features/workbench/presentation/sleep_workspace_dialog.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_host_marker.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_relocation_dialog.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_relocation_recovery_launcher.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_removal_launcher.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_tags_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

part 'workspace_actions_sheet_archive.dart';
part 'workspace_actions_sheet_linked_issue.dart';
part 'workspace_actions_sheet_menu.dart';
part 'workspace_actions_sheet_sections.dart';

enum _WorkspaceAction {
  relocate,
  recovery,
  rename,
  pin,
  unpin,
  pinTree,
  unpinTree,
  tags,
  configureParent,
  unlinkParent,
  setSection,
  setSectionTree,
  newSection,
  newSectionTree,
  clearSection,
  clearSectionTree,
  openIssue,
  linkIssue,
  changeIssue,
  unlinkIssue,
  openRepository,
  copyPath,
  sleep,
  archive,
  unarchive,
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
  final issues = ref.read(linkedIssuesControllerProvider(hostId)).value;
  final linkedIssue = issues?.byWorkspace[workspace.id];
  final descendantIds = workspaceDescendantIds(data.workspaces, workspace.id);
  final hasDescendants = descendantIds.isNotEmpty;
  final treeIds = <String>{workspace.id, ...descendantIds};
  final hasTreeSection = data.workspaces.any(
    (item) => treeIds.contains(item.id) && item.sectionId != null,
  );
  final action = await showModalBottomSheet<_WorkspaceAction>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: .min,
          children: <Widget>[
            _WorkspaceActionsHeader(
              workspace: workspace,
              host: ref
                  .read(workspaceHostsControllerProvider(hostId))
                  .value
                  ?.hostOf(workspace),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: _workspaceActionTiles(
                  context,
                  ref: ref,
                  hostId: hostId,
                  workspace: workspace,
                  data: data,
                  hasDescendants: hasDescendants,
                  hasTreeSection: hasTreeSection,
                  linkedIssueSupported: issues?.supported ?? false,
                  hasLinkedIssue: linkedIssue != null,
                ),
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
      case _WorkspaceAction.recovery:
        await showWorkspaceRecoveryFlow(
          context,
          hostId: hostId,
          workspace: workspace,
        );
      case _WorkspaceAction.relocate:
        await showWorkspaceRelocationDialog(
          context,
          hostId: hostId,
          workspace: workspace,
        );
      case _WorkspaceAction.rename:
        final name = await _promptForWorkspaceName(context, workspace.name);
        if (name != null) await controller.renameWorkspace(workspace.id, name);
      case _WorkspaceAction.pin:
        await controller.setPinned(workspace.id, true);
      case _WorkspaceAction.unpin:
        await controller.setPinned(workspace.id, false);
      case _WorkspaceAction.pinTree:
        await controller.setTreePinned(workspace.id, true);
      case _WorkspaceAction.unpinTree:
        await controller.setTreePinned(workspace.id, false);
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
      case _WorkspaceAction.setSection ||
          _WorkspaceAction.setSectionTree ||
          _WorkspaceAction.newSection ||
          _WorkspaceAction.newSectionTree ||
          _WorkspaceAction.clearSection ||
          _WorkspaceAction.clearSectionTree:
        await _runSectionAction(
          context,
          controller,
          hostId: hostId,
          workspace: workspace,
          data: data,
          action: action,
        );
      case _WorkspaceAction.tags:
        await showWorkspaceTagsSheet(
          context,
          ref,
          hostId: hostId,
          workspace: workspace,
          data: data,
        );
      case _WorkspaceAction.openIssue ||
          _WorkspaceAction.linkIssue ||
          _WorkspaceAction.changeIssue ||
          _WorkspaceAction.unlinkIssue:
        await _runLinkedIssueAction(
          context,
          ref,
          hostId: hostId,
          workspace: workspace,
          url: linkedIssue?.url,
          action: action,
        );
      case _WorkspaceAction.openRepository:
        final remote = await controller.repositoryRemoteUrl(workspace.id);
        final uri = remote == null ? null : _repositoryUri(remote);
        if (uri == null || !await launchUrl(uri)) {
          throw StateError('Repository URL is not available.');
        }
      case _WorkspaceAction.copyPath:
        await Clipboard.setData(ClipboardData(text: workspace.path));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Workspace path copied')),
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
      case _WorkspaceAction.archive || _WorkspaceAction.unarchive:
        await _runArchiveAction(
          context,
          controller,
          workspace: workspace,
          action: action,
        );
      case _WorkspaceAction.delete:
        await confirmAndDeleteWorkspace(context, controller, workspace, data);
    }
  } on Object catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Workspace action failed: $error')),
      );
    }
  }
}

class const _WorkspaceActionsHeader({
  required final WorkspaceSummary workspace,
  final MobileWorkspaceHost? host,
}) extends StatelessWidget {
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
        crossAxisAlignment: .start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  workspace.name,
                  maxLines: 1,
                  overflow: .ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: .w600,
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
                    overflow: .ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AleraTokens.foregroundMuted,
                      fontFamily: AleraTokens.monoFontFamily,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (host case final owner?) ...<Widget>[
            const SizedBox(height: AleraTokens.space8),
            Row(
              key: const Key('workspace-actions-host'),
              children: <Widget>[
                WorkspaceHostMarker(host: owner, size: AleraTokens.space16),
                const SizedBox(width: AleraTokens.space6),
                Expanded(
                  child: Text(
                    owner.label,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AleraTokens.foregroundMuted,
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
