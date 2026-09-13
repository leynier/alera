import 'dart:async';

import 'package:alera_mobile/src/app/theme/alera_tokens.dart';
import 'package:alera_mobile/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_empty_state.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_notice.dart';
import 'package:alera_mobile/src/design_system/feedback/alera_refresh_progress.dart';
import 'package:alera_mobile/src/design_system/icons/alera_file_icon.dart';
import 'package:alera_mobile/src/design_system/icons/alera_icons.dart';
import 'package:alera_mobile/src/design_system/layout/alera_section_header.dart';
import 'package:alera_mobile/src/features/runtime/domain/mobile_workspace_panels.dart';
import 'package:alera_mobile/src/design_system/forms/alera_search_field.dart';
import 'package:alera_mobile/src/design_system/menus/alera_action_sheet.dart';
import 'package:alera_mobile/src/features/workbench/application/mobile_view_prefs_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_controller.dart';
import 'package:alera_mobile/src/features/workbench/application/source_control_view_controller.dart';
import 'package:alera_mobile/src/features/workbench/domain/mobile_view_prefs.dart';
import 'package:alera_mobile/src/features/workbench/domain/source_control_rows.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_diff_viewer_screen.dart';
import 'package:alera_mobile/src/features/workbench/presentation/workspace_path_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'source_control_panel_rows.dart';

enum _SourceControlViewOption { viewMode, groupMode, collapseAll }

class const SourceControlPanel({
  super.key,
  required final String hostId,
  required final String workspaceId,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      sourceControlControllerProvider(hostId, workspaceId),
    );
    void reload() => unawaited(
      ref
          .read(sourceControlControllerProvider(hostId, workspaceId).notifier)
          .reload(),
    );
    // The last snapshot wins over a reload: a host reconnect rebuilds this
    // provider, and a spinner there would drop the list and its scroll offset.
    // Checked before the error arm so a failed refresh keeps the list too.
    final snapshot = state.value;
    if (snapshot == null) {
      return switch (state) {
        AsyncError(:final error) => AleraEmptyState(
          icon: AleraIcons.gitCompare,
          message: error.toString(),
          action: FilledButton(onPressed: reload, child: const Text('Retry')),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      };
    }
    return Column(
      children: <Widget>[
        AleraRefreshProgress(refreshing: state.isLoading),
        if (state.error case final error?)
          Padding(
            padding: AleraTokens.contentPadding,
            child: AleraNotice(
              icon: AleraIcons.warning,
              message: 'Could not refresh source control. $error',
              action: TextButton(onPressed: reload, child: const Text('Retry')),
            ),
          ),
        Expanded(
          child: _Body(
            hostId: hostId,
            workspaceId: workspaceId,
            snapshot: snapshot,
            onRefresh: reload,
          ),
        ),
      ],
    );
  }
}

class const _Body({
  required final String hostId,
  required final String workspaceId,
  required final MobileGitStatusSnapshot snapshot,
  required final VoidCallback onRefresh,
}) extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refreshAction = TextButton(
      onPressed: onRefresh,
      child: const Text('Refresh'),
    );
    if (!snapshot.isRepository) {
      return AleraEmptyState(
        icon: AleraIcons.gitBranch,
        title: 'No repository',
        message: 'This workspace is not a Git repository.',
        action: refreshAction,
      );
    }
    if (snapshot.entries.isEmpty) {
      return AleraEmptyState(
        icon: AleraIcons.check,
        title: 'Clean working tree',
        message: snapshot.branch == null
            ? 'There are no local changes.'
            : 'There are no local changes on ${snapshot.branch}.',
        action: refreshAction,
      );
    }
    // Shared with the desktop through the runtime view prefs; an older host
    // without them keeps the desktop defaults.
    final prefs = ref.watch(mobileViewPrefsControllerProvider(hostId)).value;
    final viewMode = prefs?.gitDiffViewMode ?? MobileGitDiffViewMode.tree;
    final groupMode = prefs?.gitDiffGroupMode ?? MobileGitDiffGroupMode.byArea;
    final viewProvider = sourceControlViewControllerProvider(
      hostId,
      workspaceId,
    );
    final view = ref.watch(viewProvider);
    final viewNotifier = ref.read(viewProvider.notifier);
    final sections = sourceControlSections(
      filterSourceControlChanges(snapshot.entries, view.filter),
      groupMode,
    );
    final rows = sourceControlRows(
      sections,
      viewMode: viewMode,
      collapsedKeys: view.collapsedKeys,
    );
    final collapsibleKeys = sourceControlCollapsibleKeys(
      sections,
      viewMode: viewMode,
    );
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AleraTokens.space24),
      itemCount: rows.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _Header(
            snapshot: snapshot,
            onRefresh: onRefresh,
            view: view,
            onToggleFilter: viewNotifier.toggleFilterVisible,
            onFilterChanged: viewNotifier.setFilter,
            onShowViewOptions: () => unawaited(
              _showViewOptions(
                context,
                ref,
                viewMode: viewMode,
                groupMode: groupMode,
                allCollapsed:
                    collapsibleKeys.isNotEmpty &&
                    collapsibleKeys.every(view.collapsedKeys.contains),
                onToggleAllCollapsed: () =>
                    viewNotifier.toggleAllCollapsed(collapsibleKeys),
              ),
            ),
            noMatches: sections.isEmpty,
          );
        }
        return switch (rows[index - 1]) {
          SourceControlSectionRow(:final section) => _SectionRow(
            section: section,
            collapsed: view.collapsedKeys.contains(section.key),
            onTap: () => viewNotifier.toggleCollapsed(section.key),
          ),
          SourceControlDirectoryRow(
            :final name,
            :final nodeKey,
            :final depth,
            :final fileCount,
          ) =>
            _DirectoryRow(
              name: name,
              depth: depth,
              fileCount: fileCount,
              collapsed: view.collapsedKeys.contains(nodeKey),
              onTap: () => viewNotifier.toggleCollapsed(nodeKey),
            ),
          SourceControlFileRow(
            :final change,
            :final depth,
            :final showParent,
          ) =>
            _ChangeRow(
              change: change,
              depth: depth,
              showParent: showParent,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => WorkspaceDiffViewerScreen(
                    hostId: hostId,
                    workspaceId: workspaceId,
                    change: change,
                  ),
                ),
              ),
            ),
        };
      },
    );
  }

  Future<void> _showViewOptions(
    BuildContext context,
    WidgetRef ref, {
    required MobileGitDiffViewMode viewMode,
    required MobileGitDiffGroupMode groupMode,
    required bool allCollapsed,
    required VoidCallback onToggleAllCollapsed,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final prefs = ref.read(mobileViewPrefsControllerProvider(hostId).notifier);
    final tree = viewMode == MobileGitDiffViewMode.tree;
    final byArea = groupMode == MobileGitDiffGroupMode.byArea;
    final choice = await showAleraActionSheet<_SourceControlViewOption>(
      context,
      entries: <AleraActionSheetEntry<_SourceControlViewOption>>[
        AleraActionSheetEntry<_SourceControlViewOption>(
          value: .viewMode,
          label: tree ? 'Show Flat List' : 'Show Tree',
          leading: Icon(tree ? AleraIcons.listView : AleraIcons.treeView),
        ),
        AleraActionSheetEntry<_SourceControlViewOption>(
          value: .groupMode,
          label: byArea ? 'Show All Changes' : 'Group By Staged State',
          leading: Icon(byArea ? AleraIcons.ungrouped : AleraIcons.groupByArea),
        ),
        AleraActionSheetEntry<_SourceControlViewOption>(
          value: .collapseAll,
          label: allCollapsed ? 'Expand All' : 'Collapse All',
          leading: Icon(
            allCollapsed ? AleraIcons.expandAll : AleraIcons.collapseAll,
          ),
        ),
      ],
    );
    try {
      switch (choice) {
        case _SourceControlViewOption.viewMode:
          await prefs.setGitDiffViewMode(
            tree ? MobileGitDiffViewMode.flat : MobileGitDiffViewMode.tree,
          );
        case _SourceControlViewOption.groupMode:
          await prefs.setGitDiffGroupMode(
            byArea
                ? MobileGitDiffGroupMode.unified
                : MobileGitDiffGroupMode.byArea,
          );
        case _SourceControlViewOption.collapseAll:
          onToggleAllCollapsed();
        case null:
          break;
      }
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not change the view: $error')),
      );
    }
  }
}

class const _Header({
  required final MobileGitStatusSnapshot snapshot,
  required final VoidCallback onRefresh,
  required final SourceControlViewState view,
  required final VoidCallback onToggleFilter,
  required final ValueChanged<String> onFilterChanged,
  required final VoidCallback onShowViewOptions,
  required final bool noMatches,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: .stretch,
      children: <Widget>[
        const Padding(
          padding: AleraTokens.contentPadding,
          child: AleraNotice(
            icon: AleraIcons.info,
            message: 'Read-only on mobile. Stage, unstage, and commit stay on desktop.',
          ),
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: _Summary(snapshot: snapshot, onRefresh: onRefresh),
            ),
            AleraIconButton(
              tooltip: view.filterVisible ? 'Hide File Filter' : 'Filter Files',
              icon: AleraIcons.filter,
              iconColor: view.filterVisible
                  ? AleraTokens.foreground
                  : AleraTokens.foregroundMuted,
              onPressed: onToggleFilter,
            ),
            AleraIconButton(
              tooltip: 'View Options',
              icon: AleraIcons.tune,
              onPressed: onShowViewOptions,
            ),
            const SizedBox(width: AleraTokens.space8),
          ],
        ),
        if (view.filterVisible)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space16,
            ),
            child: AleraSearchField(
              hintText: 'Filter files...',
              autofocus: true,
              onChanged: onFilterChanged,
            ),
          ),
        if (noMatches)
          const Padding(
            padding: AleraTokens.contentPadding,
            child: Text('No changed files match the filter.'),
          ),
      ],
    );
  }
}

class const _Summary({
  required final MobileGitStatusSnapshot snapshot,
  required final VoidCallback onRefresh,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileCount = snapshot.changedFileCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AleraTokens.space16,
        0,
        AleraTokens.space16,
        AleraTokens.space8,
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            AleraIcons.gitBranch,
            size: 16,
            color: AleraTokens.foregroundMuted,
          ),
          const SizedBox(width: AleraTokens.space8),
          Expanded(
            child: Text(
              snapshot.branch ?? 'Detached',
              maxLines: 1,
              overflow: .ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          Text(
            '$fileCount ${fileCount == 1 ? 'file' : 'files'}',
            style: theme.textTheme.bodySmall,
          ),
          if (snapshot.addedLineCount > 0) ...<Widget>[
            const SizedBox(width: AleraTokens.space8),
            Text(
              '+${snapshot.addedLineCount}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.success,
              ),
            ),
          ],
          if (snapshot.removedLineCount > 0) ...<Widget>[
            const SizedBox(width: AleraTokens.space8),
            Text(
              '-${snapshot.removedLineCount}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AleraTokens.error,
              ),
            ),
          ],
          const SizedBox(width: AleraTokens.space4),
          AleraIconButton(
            tooltip: 'Refresh',
            icon: AleraIcons.refresh,
            onPressed: onRefresh,
          ),
        ],
      ),
    );
  }
}
