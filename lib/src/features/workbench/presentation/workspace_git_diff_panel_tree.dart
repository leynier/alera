part of 'workspace_git_diff_panel.dart';

class _GitDiffTree extends StatefulWidget {
  const _GitDiffTree({
    required this.rows,
    required this.busy,
    required this.onOpenGitDiff,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
  });

  final List<GitChangeTreeRow> rows;
  final bool busy;
  final OpenGitDiffTabCallback onOpenGitDiff;
  final ValueChanged<GitChangeEntry> onStage;
  final ValueChanged<GitChangeEntry> onUnstage;
  final ValueChanged<GitChangeEntry> onDiscard;

  @override
  State<_GitDiffTree> createState() => _GitDiffTreeState();
}

class _GitDiffTreeState extends State<_GitDiffTree> {
  final Set<String> _collapsed = <String>{};

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows.isEmpty ? _fallbackRows() : widget.rows;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[for (final row in _visibleRows(rows)) _buildRow(row)],
    );
  }

  Iterable<GitChangeTreeRow> _visibleRows(List<GitChangeTreeRow> rows) sync* {
    int? collapsedDepth;
    for (final row in rows) {
      final hiddenDepth = collapsedDepth;
      if (hiddenDepth != null) {
        if (row.depth > hiddenDepth) {
          continue;
        }
        collapsedDepth = null;
      }
      yield row;
      if (row.kind == GitChangeTreeRowKind.directory &&
          _collapsed.contains(row.path)) {
        collapsedDepth = row.depth;
      }
    }
  }

  Widget _buildRow(GitChangeTreeRow row) {
    if (row.entry case final entry?) {
      return _GitDiffFileRow(
        entry: entry,
        depth: row.depth,
        busy: widget.busy,
        onStage: widget.onStage,
        onUnstage: widget.onUnstage,
        onDiscard: widget.onDiscard,
        onTap: () => unawaited(
          widget.onOpenGitDiff(
            relativePath: entry.path,
            area: entry.area,
            scope: WorkspaceGitDiffScope.file,
          ),
        ),
      );
    }
    final collapsed = _collapsed.contains(row.path);
    return _GitDiffDirectoryRow(
      row: row,
      collapsed: collapsed,
      onTap: () {
        setState(() {
          if (!_collapsed.add(row.path)) {
            _collapsed.remove(row.path);
          }
        });
      },
    );
  }

  List<GitChangeTreeRow> _fallbackRows() {
    return const <GitChangeTreeRow>[];
  }
}

class _GitDiffDirectoryRow extends StatelessWidget {
  const _GitDiffDirectoryRow({
    required this.row,
    required this.collapsed,
    required this.onTap,
  });

  final GitChangeTreeRow row;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _GitDiffBaseRow(
      depth: row.depth,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Icon(
            collapsed ? Icons.chevron_right : Icons.expand_more,
            size: 14,
            color: AleraTokens.foregroundMuted,
          ),
          const SizedBox(width: AleraTokens.space2),
          AleraFileIcon(
            pathOrName: row.name,
            kind: AleraFileIconKind.folder,
            isExpanded: !collapsed,
            size: 15,
          ),
          const SizedBox(width: AleraTokens.space6),
          Expanded(
            child: Text(
              row.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
          Text(
            '${row.fileCount}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AleraTokens.foregroundFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _GitDiffFileRow extends StatelessWidget {
  const _GitDiffFileRow({
    required this.entry,
    required this.depth,
    required this.onTap,
    required this.busy,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
    this.showRelativePath = false,
  });

  final GitChangeEntry entry;
  final int depth;
  final VoidCallback onTap;
  final bool busy;
  final ValueChanged<GitChangeEntry> onStage;
  final ValueChanged<GitChangeEntry> onUnstage;
  final ValueChanged<GitChangeEntry> onDiscard;
  final bool showRelativePath;

  @override
  Widget build(BuildContext context) {
    return _GitDiffBaseRow(
      depth: depth,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 16),
          AleraFileIcon(
            pathOrName: entry.path,
            kind: AleraFileIconKind.file,
            size: 15,
          ),
          const SizedBox(width: AleraTokens.space6),
          Expanded(
            child: Text(
              showRelativePath ? entry.path : entry.path.split('/').last,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AleraTokens.foregroundMuted,
              ),
            ),
          ),
          _GitStatusLabel(status: entry.status),
          const SizedBox(width: AleraTokens.space6),
          _LineStats(added: entry.added, removed: entry.removed),
          const SizedBox(width: AleraTokens.space4),
          _GitFileActions(
            entry: entry,
            busy: busy,
            onStage: onStage,
            onUnstage: onUnstage,
            onDiscard: onDiscard,
          ),
        ],
      ),
    );
  }
}

class _GitFileActions extends StatelessWidget {
  const _GitFileActions({
    required this.entry,
    required this.busy,
    required this.onStage,
    required this.onUnstage,
    required this.onDiscard,
  });

  final GitChangeEntry entry;
  final bool busy;
  final ValueChanged<GitChangeEntry> onStage;
  final ValueChanged<GitChangeEntry> onUnstage;
  final ValueChanged<GitChangeEntry> onDiscard;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 58,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          if (entry.area == GitChangeArea.staged)
            AleraIconButton(
              tooltip: 'Unstage',
              icon: Icons.remove,
              onPressed: busy ? null : () => onUnstage(entry),
            )
          else
            AleraIconButton(
              tooltip: 'Stage',
              icon: Icons.add,
              onPressed: busy ? null : () => onStage(entry),
            ),
          if (entry.area != GitChangeArea.staged)
            AleraIconButton(
              tooltip: 'Discard',
              icon: Icons.close,
              onPressed: busy ? null : () => onDiscard(entry),
            ),
        ],
      ),
    );
  }
}

class _GitDiffBaseRow extends StatelessWidget {
  const _GitDiffBaseRow({
    required this.depth,
    required this.child,
    required this.onTap,
  });

  final int depth;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.only(
            left: AleraTokens.space8 + (depth * AleraTokens.space12),
            right: AleraTokens.space8,
            top: AleraTokens.space4,
            bottom: AleraTokens.space4,
          ),
          child: child,
        ),
      ),
    );
  }
}

class _LineStats extends StatelessWidget {
  const _LineStats({required this.added, required this.removed});

  final int? added;
  final int? removed;

  @override
  Widget build(BuildContext context) {
    final visibleAdded = added != null && added! > 0 ? added : null;
    final visibleRemoved = removed != null && removed! > 0 ? removed : null;
    if (visibleAdded == null && visibleRemoved == null) {
      return const SizedBox(width: 64);
    }
    final style = Theme.of(context).textTheme.labelSmall;
    return SizedBox(
      width: 64,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: <Widget>[
          if (visibleAdded case final added?)
            Flexible(
              child: Text(
                '+$added',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style?.copyWith(color: AleraTokens.success),
              ),
            ),
          if (visibleRemoved case final removed?) ...<Widget>[
            const SizedBox(width: AleraTokens.space4),
            Flexible(
              child: Text(
                '-$removed',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style?.copyWith(color: AleraTokens.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GitStatusLabel extends StatelessWidget {
  const _GitStatusLabel({required this.status});

  final GitChangeStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      GitChangeStatus.added => ('A', AleraTokens.success),
      GitChangeStatus.untracked => ('U', AleraTokens.success),
      GitChangeStatus.deleted => ('D', AleraTokens.error),
      GitChangeStatus.renamed => ('R', AleraTokens.warning),
      GitChangeStatus.copied => ('C', AleraTokens.warning),
      GitChangeStatus.modified => ('M', AleraTokens.warning),
    };
    return SizedBox(
      width: 12,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
