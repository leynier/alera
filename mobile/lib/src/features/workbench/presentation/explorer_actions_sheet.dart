import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/menus/alera_action_sheet.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/explorer_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workspace_panels_controller.dart';
import 'package:alera_mobile/src/features/workbench/domain/host_absolute_path.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_file_viewer_screen.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/application/workspace_agent_comment_controller.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/presentation/workspace_agent_comment_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

final Logger _logger = Logger('ExplorerActionsSheet');

enum ExplorerAction {
  open,
  comment,
  copyPath,
  copyRelativePath,
  collapse,
  useAsSourceControlRoot,
  clearSourceControlRoot,
}

/// Read and navigation actions for one explorer row. File mutation stays on
/// desktop, so nothing here writes the tree.
List<AleraActionSheetEntry<ExplorerAction>> explorerActionEntries({
  required ExplorerRow row,
  required String? sourceControlRoot,
  required bool supportsSourceControlRoot,
}) {
  final entry = row.entry;
  final isRoot = entry.relativePath == sourceControlRoot;
  return <AleraActionSheetEntry<ExplorerAction>>[
    if (entry.isFile) ...<AleraActionSheetEntry<ExplorerAction>>[
      const AleraActionSheetEntry(
        value: ExplorerAction.open,
        label: 'Open File',
        leading: Icon(AleraIcons.files, size: 20),
      ),
      const AleraActionSheetEntry(
        value: ExplorerAction.comment,
        label: 'Comment on File',
        leading: Icon(AleraIcons.comment, size: 20),
      ),
    ],
    const AleraActionSheetEntry(
      value: ExplorerAction.copyPath,
      label: 'Copy Path',
      leading: Icon(AleraIcons.copy, size: 20),
    ),
    const AleraActionSheetEntry(
      value: ExplorerAction.copyRelativePath,
      label: 'Copy Relative Path',
      leading: Icon(AleraIcons.copy, size: 20),
    ),
    if (entry.isDirectory && row.expanded)
      const AleraActionSheetEntry(
        value: ExplorerAction.collapse,
        label: 'Collapse Folder',
        leading: Icon(AleraIcons.chevronRight, size: 20),
      ),
    if (entry.isDirectory && isRoot)
      const AleraActionSheetEntry(
        value: ExplorerAction.clearSourceControlRoot,
        label: 'Clear Source Control Root',
        leading: Icon(AleraIcons.close, size: 20),
      )
    else if (entry.isDirectory && supportsSourceControlRoot)
      const AleraActionSheetEntry(
        value: ExplorerAction.useAsSourceControlRoot,
        label: 'Use As Source Control Root',
        leading: Icon(AleraIcons.gitBranch, size: 20),
      ),
  ];
}

Future<void> showExplorerActionsSheet(
  BuildContext context,
  WidgetRef ref, {
  required String hostId,
  required WorkspaceSummary workspace,
  required ExplorerRow row,
  required String? sourceControlRoot,
  required bool supportsSourceControlRoot,
}) async {
  final action = await showAleraActionSheet<ExplorerAction>(
    context,
    entries: explorerActionEntries(
      row: row,
      sourceControlRoot: sourceControlRoot,
      supportsSourceControlRoot: supportsSourceControlRoot,
    ),
  );
  if (action == null || !context.mounted) {
    return;
  }
  final messenger = ScaffoldMessenger.of(context);
  final entry = row.entry;
  final explorer = ref.read(
    explorerControllerProvider(hostId, workspace.id).notifier,
  );
  void notify(String message) {
    if (messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  try {
    switch (action) {
      case ExplorerAction.open:
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => WorkspaceFileViewerScreen(
              hostId: hostId,
              workspaceId: workspace.id,
              relativePath: entry.relativePath,
            ),
          ),
        );
      case ExplorerAction.comment:
        final body = await showWorkspaceAgentCommentDialog(
          context,
          path: entry.relativePath,
        );
        if (body != null) {
          ref
              .read(
                workspaceAgentCommentControllerProvider(
                  hostId,
                  workspace.id,
                ).notifier,
              )
              .add(path: entry.relativePath, body: body);
        }
      case ExplorerAction.copyPath:
        await Clipboard.setData(
          ClipboardData(
            text: hostAbsolutePath(
              rootPath: workspace.path,
              relativePath: entry.relativePath,
            ),
          ),
        );
        notify('Path copied');
      case ExplorerAction.copyRelativePath:
        await Clipboard.setData(ClipboardData(text: entry.relativePath));
        notify('Relative path copied');
      case ExplorerAction.collapse:
        await explorer.toggle(entry);
      case ExplorerAction.useAsSourceControlRoot:
        switch (await explorer.useAsSourceControlRoot(entry.relativePath)) {
          case SourceControlRootResult.applied:
            ref
                .read(
                  selectedWorkspacePanelControllerProvider(
                    hostId,
                    workspace.id,
                  ).notifier,
                )
                .select(WorkspacePanelDestination.sourceControl);
          case SourceControlRootResult.notRepository:
            notify('Folder is not a Git repository');
          case SourceControlRootResult.unsupported:
            notify(
              'Update the paired Alera runtime to use a source control root.',
            );
        }
      case ExplorerAction.clearSourceControlRoot:
        await explorer.clearSourceControlRoot();
        notify('Source control root cleared');
    }
  } on Object catch (error, stackTrace) {
    _logger.warning('explorer action ${action.name} failed', error, stackTrace);
    notify('Explorer action failed: $error');
  }
}
