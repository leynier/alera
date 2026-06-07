import 'dart:async';

import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/icons/alera_file_icon.dart';
import 'package:alera/src/features/workbench/domain/workbench_view_prefs.dart';
import 'package:alera/src/features/workbench/domain/workspace.dart';
import 'package:alera/src/features/workbench/domain/workspace_tab_record.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

part 'workspace_git_diff_panel_tree.dart';

typedef OpenGitDiffTabCallback =
    Future<void> Function({
      String? relativePath,
      GitChangeArea? area,
      required WorkspaceGitDiffScope scope,
    });

class WorkspaceGitDiffPanel extends ConsumerStatefulWidget {
  const WorkspaceGitDiffPanel({
    super.key,
    required this.workspace,
    required this.viewMode,
    required this.onViewModeChanged,
    required this.onOpenGitDiff,
  });

  final Workspace workspace;
  final GitDiffViewMode viewMode;
  final ValueChanged<GitDiffViewMode> onViewModeChanged;
  final OpenGitDiffTabCallback onOpenGitDiff;

  @override
  ConsumerState<WorkspaceGitDiffPanel> createState() =>
      _WorkspaceGitDiffPanelState();
}

class _WorkspaceGitDiffPanelState extends ConsumerState<WorkspaceGitDiffPanel> {
  Future<GitStatusResult>? _statusFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant WorkspaceGitDiffPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace.path != widget.workspace.path) {
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _GitDiffToolbar(
          viewMode: widget.viewMode,
          onViewModeChanged: widget.onViewModeChanged,
          onRefresh: _refresh,
          onOpenAll: () =>
              unawaited(widget.onOpenGitDiff(scope: WorkspaceGitDiffScope.all)),
        ),
        const Divider(height: 1, color: AleraTokens.borderSubtle),
        Expanded(
          child: FutureBuilder<GitStatusResult>(
            future: _statusFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return _GitDiffMessage(message: _messageFor(snapshot.error));
              }
              final entries =
                  snapshot.data?.entries ?? const <GitChangeEntry>[];
              if (entries.isEmpty) {
                return const _GitDiffMessage(message: 'No changes');
              }
              return _GitDiffGroups(
                entries: entries,
                viewMode: widget.viewMode,
                onOpenGitDiff: widget.onOpenGitDiff,
              );
            },
          ),
        ),
      ],
    );
  }

  void _refresh() {
    setState(() {
      _statusFuture = ref
          .read(gitBackendProvider)
          .status(widget.workspace.path);
    });
  }

  String _messageFor(Object? error) {
    if (error is NotARepositoryException) {
      return 'This workspace is not a Git repository.';
    }
    return 'Could not load Git changes.';
  }
}

class _GitDiffToolbar extends StatelessWidget {
  const _GitDiffToolbar({
    required this.viewMode,
    required this.onViewModeChanged,
    required this.onRefresh,
    required this.onOpenAll,
  });

  final GitDiffViewMode viewMode;
  final ValueChanged<GitDiffViewMode> onViewModeChanged;
  final VoidCallback onRefresh;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AleraTokens.sidebarHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AleraTokens.space8),
        child: Row(
          children: <Widget>[
            Text(
              'Source Control',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Spacer(),
            AleraIconButton(
              tooltip: 'All changes',
              icon: Icons.difference_outlined,
              onPressed: onOpenAll,
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: viewMode == GitDiffViewMode.tree
                  ? 'Show flat list'
                  : 'Show tree',
              icon: viewMode == GitDiffViewMode.tree
                  ? Icons.view_list_outlined
                  : Icons.account_tree_outlined,
              onPressed: () => onViewModeChanged(
                viewMode == GitDiffViewMode.tree
                    ? GitDiffViewMode.flat
                    : GitDiffViewMode.tree,
              ),
            ),
            const SizedBox(width: AleraTokens.space2),
            AleraIconButton(
              tooltip: 'Refresh',
              icon: Icons.refresh,
              onPressed: onRefresh,
            ),
          ],
        ),
      ),
    );
  }
}

class _GitDiffGroups extends StatelessWidget {
  const _GitDiffGroups({
    required this.entries,
    required this.viewMode,
    required this.onOpenGitDiff,
  });

  final List<GitChangeEntry> entries;
  final GitDiffViewMode viewMode;
  final OpenGitDiffTabCallback onOpenGitDiff;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AleraTokens.space6),
      children: <Widget>[
        for (final area in GitChangeArea.values)
          _GitDiffGroup(
            area: area,
            entries: entries
                .where((entry) => entry.area == area)
                .toList(growable: false),
            viewMode: viewMode,
            onOpenGitDiff: onOpenGitDiff,
          ),
      ],
    );
  }
}

class _GitDiffGroup extends StatelessWidget {
  const _GitDiffGroup({
    required this.area,
    required this.entries,
    required this.viewMode,
    required this.onOpenGitDiff,
  });

  final GitChangeArea area;
  final List<GitChangeEntry> entries;
  final GitDiffViewMode viewMode;
  final OpenGitDiffTabCallback onOpenGitDiff;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    final sorted = entries.toList(growable: false)
      ..sort((a, b) => a.path.compareTo(b.path));
    return Padding(
      padding: const EdgeInsets.only(bottom: AleraTokens.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AleraTokens.space8,
              vertical: AleraTokens.space4,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    area.label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AleraTokens.foregroundMuted,
                    ),
                  ),
                ),
                Text(
                  '${entries.length}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AleraTokens.foregroundFaint,
                  ),
                ),
              ],
            ),
          ),
          if (viewMode == GitDiffViewMode.flat)
            for (final entry in sorted)
              _GitDiffFileRow(
                entry: entry,
                depth: 0,
                showRelativePath: true,
                onTap: () => unawaited(
                  onOpenGitDiff(
                    relativePath: entry.path,
                    area: entry.area,
                    scope: WorkspaceGitDiffScope.file,
                  ),
                ),
              )
          else
            _GitDiffTree(entries: sorted, onOpenGitDiff: onOpenGitDiff),
        ],
      ),
    );
  }
}

class _GitDiffMessage extends StatelessWidget {
  const _GitDiffMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AleraTokens.space16),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AleraTokens.foregroundMuted),
        ),
      ),
    );
  }
}
