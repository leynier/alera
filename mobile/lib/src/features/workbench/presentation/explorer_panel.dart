import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_refresh_progress.dart';
import 'package:alera_mobile/src/design_system/icons/alera_file_icon.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/workbench/application/explorer_controller.dart';
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
    void reload() => unawaited(
      ref
          .read(explorerControllerProvider(hostId, workspaceId).notifier)
          .reload(),
    );
    // The last rows win over a reload, so a host reconnect does not collapse
    // the tree into a spinner; see `SourceControlPanel`.
    final view = state.value;
    if (view == null) {
      return switch (state) {
        AsyncError(:final error) => AleraEmptyState(
          icon: AleraIcons.files,
          message: error.toString(),
          action: FilledButton(onPressed: reload, child: const Text('Retry')),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      };
    }
    return Column(
      children: <Widget>[
        AleraRefreshProgress(refreshing: state.isLoading),
        AleraSectionHeader(
          label: 'Files',
          padding: const EdgeInsets.only(
            left: AleraTokens.space16,
            right: AleraTokens.space8,
          ),
          trailing: AleraIconButton(
            tooltip: 'Refresh',
            icon: AleraIcons.refresh,
            onPressed: reload,
          ),
        ),
        if (state.error case final error?)
          Padding(
            padding: AleraTokens.contentPadding,
            child: AleraNotice(
              icon: AleraIcons.warning,
              message: 'Could not refresh files. $error',
              action: TextButton(onPressed: reload, child: const Text('Retry')),
            ),
          ),
        Expanded(
          child: _ExplorerBody(
            hostId: hostId,
            workspaceId: workspaceId,
            view: view,
          ),
        ),
      ],
    );
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
              : AleraFileIcon(
                  pathOrName: row.entry.name,
                  kind: AleraFileIconKind.fromEntryKind(row.entry.kind),
                  isExpanded: row.expanded,
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
