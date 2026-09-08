import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/features/workbench/application/explorer_controller.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_file_picker_sheet.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_file_viewer_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class const ExplorerPanel({
  super.key,
  required final String hostId,
  required final String workspaceId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(explorerControllerProvider(hostId, workspaceId));
    return switch (state) {
      AsyncData(value: final view) => _ExplorerBody(
        hostId: hostId,
        workspaceId: workspaceId,
        view: view,
      ),
      AsyncError(:final error) => AleraEmptyState(
        icon: AleraIcons.files,
        message: error.toString(),
        action: FilledButton(
          onPressed: () => ref
              .read(explorerControllerProvider(hostId, workspaceId).notifier)
              .reload(),
          child: const Text('Retry'),
        ),
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}

class const _ExplorerBody({
  required final String hostId,
  required final String workspaceId,
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
    return ListView.builder(
      itemCount: view.rows.length,
      itemBuilder: (context, index) {
        final row = view.rows[index];
        return ListTile(
          contentPadding: EdgeInsets.only(
            left: AleraTokens.space16 + row.depth * AleraTokens.space20,
            right: AleraTokens.space16,
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
          trailing: row.entry.isDirectory
              ? Icon(
                  row.expanded
                      ? AleraIcons.chevronDown
                      : AleraIcons.chevronRight,
                  size: AleraTokens.iconSm,
                )
              : null,
          onTap: () {
            if (row.entry.isDirectory) {
              ref
                  .read(
                    explorerControllerProvider(hostId, workspaceId).notifier,
                  )
                  .toggle(row.entry);
              return;
            }
            Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => WorkspaceFileViewerScreen(
                  hostId: hostId,
                  workspaceId: workspaceId,
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
