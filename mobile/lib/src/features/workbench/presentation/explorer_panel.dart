import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/features/runtime/domain/workspace_summary.dart';
import 'package:alera_mobile/src/features/workbench/application/explorer_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/explorer_preferences_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/workbench_providers.dart';
import 'package:alera_mobile/src/features/workbench/presentation/explorer_actions_sheet.dart';
import 'package:alera_mobile/src/features/workbench/presentation/explorer_panel_toolbar.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_file_picker_sheet.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_file_viewer_screen.dart';
import 'package:alera_mobile/src/features/workspace_agent_comments/presentation/workspace_agent_comment_queue.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const ExplorerPanel({
  super.key,
  required final String hostId,
  required final WorkspaceSummary workspace,
  final ValueChanged<String>? onOpenTab,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = explorerControllerProvider(hostId, workspace.id);
    final state = ref.watch(provider);
    return switch (state) {
      AsyncData(value: final view) => Column(
        children: <Widget>[
          ExplorerPanelToolbar(
            title: 'Explorer',
            hideIgnored: view.hideIgnored,
            refreshing: view.refreshing,
            canCollapse: view.hasExpandedFolders,
            onToggleIgnored: () => unawaited(
              ref.read(provider.notifier).setHideIgnored(!view.hideIgnored),
            ),
            onCollapseAll: ref.read(provider.notifier).collapseAll,
            onRefresh: () => unawaited(ref.read(provider.notifier).refresh()),
          ),
          if (view.refreshing)
            const LinearProgressIndicator(minHeight: AleraTokens.space2),
          WorkspaceAgentCommentQueue(
            hostId: hostId,
            workspaceId: workspace.id,
            onOpenTab: onOpenTab,
          ),
          Expanded(
            child: _ExplorerBody(
              hostId: hostId,
              workspace: workspace,
              view: view,
            ),
          ),
        ],
      ),
      AsyncError(:final error) => AleraEmptyState(
        icon: AleraIcons.files,
        message: error.toString(),
        action: FilledButton(
          onPressed: () => ref.read(provider.notifier).reload(),
          child: const Text('Retry'),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class const _ExplorerBody({
  required final String hostId,
  required final WorkspaceSummary workspace,
  required final ExplorerViewState view,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (view.error != null && view.rows.isEmpty) {
      return AleraEmptyState(
        icon: AleraIcons.files,
        message: view.error.toString(),
      );
    }
    if (view.isEmpty) {
      return const AleraEmptyState(
        icon: AleraIcons.folder,
        title: 'Empty folder',
        message: 'This workspace has no files to show.',
      );
    }
    final sourceControlRoot = ref
        .watch(explorerPreferencesControllerProvider(hostId, workspace.id))
        .value
        ?.sourceControlRoot;
    final client = ref.watch(workspaceClientProvider(hostId)).value;
    final supportsSourceControlRoot =
        client is MobileWorkspacePanelsClient &&
        (client as MobileWorkspacePanelsClient).supportsSourceControlRoot;
    void showActions(ExplorerRow row) => unawaited(
      showExplorerActionsSheet(
        context,
        ref,
        hostId: hostId,
        workspace: workspace,
        row: row,
        sourceControlRoot: sourceControlRoot,
        supportsSourceControlRoot: supportsSourceControlRoot,
      ),
    );
    return ListView.builder(
      itemCount: view.rows.length,
      itemBuilder: (context, index) {
        final row = view.rows[index];
        final isSourceControlRoot =
            row.entry.isDirectory &&
            row.entry.relativePath == sourceControlRoot;
        return ListTile(
          contentPadding: EdgeInsets.only(
            left: AleraTokens.space16 + row.depth * AleraTokens.space20,
            right: AleraTokens.space4,
          ),
          minTileHeight: AleraTokens.minTapTarget,
          leading: row.loadingChildren
              ? const SizedBox(
                  width: AleraTokens.space20,
                  height: AleraTokens.space20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  row.entry.isDirectory
                      ? (row.expanded
                            ? AleraIcons.folderOpen
                            : AleraIcons.folder)
                      : workspaceFileIcon(row.entry.relativePath),
                ),
          title: Text(row.entry.name),
          trailing: Row(
            mainAxisSize: .min,
            children: <Widget>[
              if (isSourceControlRoot)
                const Tooltip(
                  message: 'Source control root',
                  child: Icon(
                    AleraIcons.gitBranch,
                    size: AleraTokens.iconSm,
                    color: AleraTokens.foregroundMuted,
                  ),
                ),
              if (row.entry.isDirectory)
                Icon(
                  row.expanded
                      ? AleraIcons.chevronDown
                      : AleraIcons.chevronRight,
                  size: AleraTokens.iconSm,
                ),
              AleraIconButton(
                tooltip: 'File Actions',
                onPressed: () => showActions(row),
                icon: AleraIcons.more,
              ),
            ],
          ),
          onLongPress: () => showActions(row),
          onTap: () {
            if (row.entry.isDirectory) {
              ref
                  .read(
                    explorerControllerProvider(hostId, workspace.id).notifier,
                  )
                  .toggle(row.entry);
              return;
            }
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => WorkspaceFileViewerScreen(
                  hostId: hostId,
                  workspaceId: workspace.id,
                  relativePath: row.entry.relativePath,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
